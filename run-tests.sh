#!/usr/bin/env bash
set -efu

HOSTIP=`hostname -i | cut -f1 -d' '`

CH_CONTAINER_NAME=test-clickhouse-server
ERRATA_CONTAINER_NAME=test-errata-service

TEST_PORT=9222
TEST_CONFIG=test-config.yml
TEST_DOCKER_COMPOSE=test-docker-compose.yml

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

clean_up () {
    echo "Removing test containers and files"

    # stop test ErrataID service
    docker stop $ERRATA_CONTAINER_NAME && docker rm $ERRATA_CONTAINER_NAME

    # stop test ClickhouseServer
    docker stop $CH_CONTAINER_NAME && docker rm $CH_CONTAINER_NAME

    # delete tempoarary config files
    rm -f $TEST_CONFIG $TEST_DOCKER_COMPOSE
}

ok () {
    echo -e "${GREEN}INFO: $1${NC}"
}

fatal () {
    echo -e "${RED}ERROR: $1${NC}"
    clean_up
    exit 1
}

warn () {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

# run ErrataID service unit tests
echo "Run ErrataID service unit tests"
docker compose -f docker-compose.tests.yml up --build
rc=`docker inspect -f {{.State.ExitCode}} $ERRATA_CONTAINER_NAME`
echo $rc
[[ $rc == 0 ]] && ok "Unit tests: PASSED "|| echo -e "${RED}ERROR: Unit tests: FAILED${NC}"
docker rm $ERRATA_CONTAINER_NAME

# run ClickHouse server container
docker run -d -p 18123:8123 -p19000:9000 --name $CH_CONTAINER_NAME --ulimit nofile=262144:262144 clickhouse/clickhouse-server || warn "'$CH_CONTAINER_NAME' container already running"

until [ "`docker inspect -f {{.State.Status}} $CH_CONTAINER_NAME`"=="runnig" ]; do
    sleep 1;
done;

# create ErrataID table using curl and ClickHouse HTTP interface
sleep 3
cat config/errata.sql | curl http://$HOSTIP:18123/ --data-binary @- || fatal "Failed to create table in DB"

# create test config
cat >$TEST_CONFIG<<EOF
name: test_ErrataID
port: $TEST_PORT
database: default
login: default
password: ""
clickhouse_address: $HOSTIP:19000
dialTimeout: 5
HTTP: false
allowed: ["0.0.0.0/0"]
EOF

# create test docker-compose file
cat >$TEST_DOCKER_COMPOSE<<EOF
services:
  service-test:
    container_name: $ERRATA_CONTAINER_NAME
    environment:
      - TZ=Europe/Moscow
    build:
      context: .
      dockerfile: Dockerfile
    volumes:
      - ./$TEST_CONFIG:/service/config.yml
    ports:
      - $TEST_PORT:$TEST_PORT
EOF

# run service in container with test CH database
docker compose -f $TEST_DOCKER_COMPOSE up -d --build || fatal "Failed to run '$ERRATA_CONTAINER_NAME' container"

until [ "`docker inspect -f {{.State.Status}} $ERRATA_CONTAINER_NAME`"=="runnig" ]; do
    sleep 1;
done;

# run actual tests here
sleep 3
# test `/version` route
## test return codes
retcode=`curl -Is -X 'GET' http://$HOSTIP:$TEST_PORT/version | head -n 1 | cut -d' ' -f2`
[[ $retcode == "200" ]] && ok "Version test #1: PASSED" || fatal "Version test #1: FAILED [service returned $retcode]"

retcode=`curl -Is -X 'POST' http://$HOSTIP:$TEST_PORT/version | head -n 1 | cut -d' ' -f2`
[[ $retcode == "405" ]] && ok "Version test #2: PASSED" || fatal "Version test #2: FAILED [service returned $retcode]"

## test version the same with latest GIT tag
errata_git_version=`git tag --sort=-version:refname | head -n 1`
errata_version=`curl -s -X 'GET' http://$HOSTIP:$TEST_PORT/version | jq -r '.version'` || fatal "Failed to get data from service"
[[ $errata_version == $errata_git_version ]] && ok "Version test #3: PASSED [$errata_version]" || fatal "Version test #3: FAILED [$errata_version != $errata_git_version]"


# test `/register` route
## test HTTP method and arguments validation
retcode=`curl -Is -X 'POST' http://$HOSTIP:$TEST_PORT/register?prefix=TEST-TEST\&year=2000 | head -n 1 | cut -d' ' -f2`
[[ $retcode == "405" ]] && ok "Register test #1: PASSED" || fatal "Register test #1: FALIED [service returned $retcode]"

retcode=`curl -Is -X 'PUT' http://$HOSTIP:$TEST_PORT/register?prefix=TEST-TEST\&year=2000 | head -n 1 | cut -d' ' -f2`
[[ $retcode == "405" ]] && ok "Register test #2: PASSED" || fatal "Register test #2: FALIED [service returned $retcode]"

retcode=`curl -Is -X 'GET' http://$HOSTIP:$TEST_PORT/register?prefix=TEST-TEST | head -n 1 | cut -d' ' -f2`
[[ $retcode == "400" ]] && ok "Register test #3: PASSED" || fatal "Register test #3: FALIED [service returned $retcode]"

retcode=`curl -Is -X 'GET' http://$HOSTIP:$TEST_PORT/register?prefix=TEST\&year=2000 | head -n 1 | cut -d' ' -f2`
[[ $retcode == "400" ]] && ok "Register test #4: PASSED" || fatal "Register test #4: FALIED [service returned $retcode]"

retcode=`curl -Is -X 'GET' http://$HOSTIP:$TEST_PORT/register?prefix=TEST-TEST\&year=1990 | head -n 1 | cut -d' ' -f2`
[[ $retcode == "400" ]] && ok "Register test #5: PASSED" || fatal "Register test #5: FALIED [service returned $retcode]"

## test errata registartion
_registered=`curl -s -X 'GET' http://$HOSTIP:$TEST_PORT/register?prefix=TEST-TEST\&year=2000` || fatal "Failed to get data from service"
errata_id=`echo $_registered | jq -r '.errata.id'`
[[ $errata_id == "TEST-TEST-2000-1000-1" ]] && ok "Register test #6: PASSED [$errata_id]" || fatal "Register test #6: FALIED [register new errata]"

_registered=`curl -s -X 'GET' http://$HOSTIP:$TEST_PORT/register?prefix=TEST-TEST\&year=2000` || fatal "Failed to get data from service"
errata_id=`echo $_registered | jq -r '.errata.id'`
[[ $errata_id == "TEST-TEST-2000-1001-1" ]] && ok "Register test #7: PASSED [$errata_id]" || fatal "Register test #7: FALIED [register new errata]"

_registered=`curl -s -X 'GET' http://$HOSTIP:$TEST_PORT/register?prefix=TEST-TEST\&year=2345` || fatal "Failed to get data from service"
errata_id=`echo $_registered | jq -r '.errata.id'`
[[ $errata_id == "TEST-TEST-2345-1000-1" ]] && ok "Register test #8: PASSED [$errata_id]" || fatal "Register test #8: FALIED [register new errata]"


# test `/check` route
## test HTTP method and arguments validation
retcode=`curl -Is -X 'POST' http://$HOSTIP:$TEST_PORT/check?name=TEST-TEST-1234-5687-9 | head -n 1 | cut -d' ' -f2`
[[ $retcode == "405" ]] && ok "Check test #1: PASSED" || fatal "Check test #1: FALIED [service returned $retcode]"

retcode=`curl -Is -X 'PUT' http://$HOSTIP:$TEST_PORT/check?name=TEST-TEST-1234-5687-9 | head -n 1 | cut -d' ' -f2`
[[ $retcode == "405" ]] && ok "Check test #2: PASSED" || fatal "Check test #2: FALIED [service returned $retcode]"

retcode=`curl -Is -X 'GET' http://$HOSTIP:$TEST_PORT/check?name=TEST-1234 | head -n 1 | cut -d' ' -f2`
[[ $retcode == "400" ]] && ok "Check test #3: PASSED" || fatal "Check test #3: FALIED [service returned $retcode]"

retcode=`curl -Is -X 'GET' http://$HOSTIP:$TEST_PORT/check | head -n 1 | cut -d' ' -f2`
[[ $retcode == "400" ]] && ok "Check test #4: PASSED" || fatal "Check test #4: FALIED [service returned $retcode]"

retcode=`curl -Is -X 'GET' http://$HOSTIP:$TEST_PORT/check?prefix=TEST | head -n 1 | cut -d' ' -f2`
[[ $retcode == "400" ]] && ok "Check test #5: PASSED" || fatal "Check test #5: FALIED [service returned $retcode]"

retcode=`curl -Is -X 'GET' http://$HOSTIP:$TEST_PORT/check?name=TEST-TEST-1234-5687-9 | head -n 1 | cut -d' ' -f2`
[[ $retcode == "400" ]] && ok "Check test #6: PASSED" || fatal "Check test #6: FALIED [service returned $retcode]"

# test errata check
retcode=`curl -Is -X 'GET' http://$HOSTIP:$TEST_PORT/check?name=TEST-TEST-2222-5687-9 | head -n 1 | cut -d' ' -f2`
[[ $retcode == "404" ]] && ok "Check test #7: PASSED" || fatal "Check test #7: FALIED [service returned $retcode]"

retcode=`curl -Is -X 'GET' http://$HOSTIP:$TEST_PORT/check?name=$errata_id | head -n 1 | cut -d' ' -f2`
[[ $retcode == "200" ]] && ok "Check test #8: PASSED" || fatal "Check test #8: FALIED [service returned $retcode]"

# test `/update` route
## test HTTP method and arguments validation
retcode=`curl -Is -X 'GET' http://$HOSTIP:$TEST_PORT/update?name=TEST-TEST-2222-5687-9 | head -n 1 | cut -d' ' -f2`
[[ $retcode == "405" ]] && ok "Update test #1: PASSED" || fatal "Update test #1: FALIED [service returned $retcode]"

retcode=`curl -Is -X 'PUT' http://$HOSTIP:$TEST_PORT/update?name=TEST-TEST-2222-5687-9 | head -n 1 | cut -d' ' -f2`
[[ $retcode == "405" ]] && ok "Update test #2: PASSED" || fatal "Update test #2: FALIED [service returned $retcode]"

retcode=`curl -Is -X 'POST' http://$HOSTIP:$TEST_PORT/update?name=TEST-1234-5678-9 | head -n 1 | cut -d' ' -f2`
[[ $retcode == "400" ]] && ok "Update test #3: PASSED" || fatal "Update test #3: FALIED [service returned $retcode]"

retcode=`curl -Is -X 'POST' http://$HOSTIP:$TEST_PORT/update | head -n 1 | cut -d' ' -f2`
[[ $retcode == "400" ]] && ok "Update test #4: PASSED" || fatal "Update test #4: FALIED [service returned $retcode]"

retcode=`curl -Is -X 'POST' http://$HOSTIP:$TEST_PORT/update?prefix=TEST-2222-5678-9 | head -n 1 | cut -d' ' -f2`
[[ $retcode == "400" ]] && ok "Update test #5: PASSED" || fatal "Update test #5: FALIED [service returned $retcode]"

## test errata update
retcode=`curl -Is -X 'POST' http://$HOSTIP:$TEST_PORT/update?name=TEST-TEST-2222-5687-9 | head -n 1 | cut -d' ' -f2`
[[ $retcode == "404" ]] && ok "Update test #6: PASSED" || fatal "Update test #6: FALIED [service returned $retcode]"

_updated=`curl -s -X 'POST' http://$HOSTIP:$TEST_PORT/update?name=$errata_id` || fatal "Failed to get data from service"
new_errata_id=`echo $_updated | jq -r '.errata.id'`
[[ $new_errata_id == "TEST-TEST-2345-1000-2" ]] && ok "Update test #7: PASSED [$errata_id > $new_errata_id]" || fatal "Update test #7: FALIED [update errata]"

_updated=`curl -s -X 'POST' http://$HOSTIP:$TEST_PORT/update?name=$new_errata_id` || fatal "Failed to get data from service"
new_new_errata_id=`echo $_updated | jq -r '.errata.id'`
[[ $new_new_errata_id == "TEST-TEST-2345-1000-3" ]] && ok "Update test #8: PASSED [$new_errata_id > $new_new_errata_id]" || fatal "Update test #8: FALIED [update errata]"

_updated=`curl -s -X 'POST' http://$HOSTIP:$TEST_PORT/update?name=$errata_id` || fatal "Failed to get data from service"
new_errata_id=`echo $_updated | jq -r '.errata.id'`
[[ -z "$new_errata_id" ]] && ok "Update test #9: PASSED" || fatal "Update test #9: FALIED"

# test `/discard` route
## test HTTP method and arguments validation
retcode=`curl -Is -X 'GET' http://$HOSTIP:$TEST_PORT/discard?name=TEST-TEST-2222-5687-9 | head -n 1 | cut -d' ' -f2`
[[ $retcode == "405" ]] && ok "Discard test #1: PASSED" || fatal "Discard test #1: FALIED [service returned $retcode]"

retcode=`curl -Is -X 'PUT' http://$HOSTIP:$TEST_PORT/discard?name=TEST-TEST-2222-5687-9 | head -n 1 | cut -d' ' -f2`
[[ $retcode == "405" ]] && ok "Discard test #2: PASSED" || fatal "Discard test #2: FALIED [service returned $retcode]"

retcode=`curl -Is -X 'POST' http://$HOSTIP:$TEST_PORT/discard?name=TEST-1234-5678-9 | head -n 1 | cut -d' ' -f2`
[[ $retcode == "400" ]] && ok "Discard test #3: PASSED" || fatal "Discard test #3: FALIED [service returned $retcode]"

retcode=`curl -Is -X 'POST' http://$HOSTIP:$TEST_PORT/discard | head -n 1 | cut -d' ' -f2`
[[ $retcode == "400" ]] && ok "Discard test #4: PASSED" || fatal "Discard test #4: FALIED [service returned $retcode]"

retcode=`curl -Is -X 'POST' http://$HOSTIP:$TEST_PORT/discard?prefix=TEST-2222-5678-9 | head -n 1 | cut -d' ' -f2`
[[ $retcode == "400" ]] && ok "Discard test #5: PASSED" || fatal "Discard test #5: FALIED [service returned $retcode]"

## test errata discard
retcode=`curl -Is -X 'POST' http://$HOSTIP:$TEST_PORT/discard?name=TEST-TEST-2222-5687-9 | head -n 1 | cut -d' ' -f2`
[[ $retcode == "404" ]] && ok "Discard test #6: PASSED" || fatal "Discard test #6: FALIED [service returned $retcode]"

errata_id_1="TEST-TEST-2345-1000-3"
errata_id_2="TEST-TEST-2345-1000-2"
errata_id_3="TEST-TEST-2345-1000-1"

_updated=`curl -s -X 'POST' http://$HOSTIP:$TEST_PORT/discard?name=$errata_id_1` || fatal "Failed to get data from service"
res_errata_id=`echo $_updated | jq -r '.errata.id'`
[[ $res_errata_id == $errata_id_1 ]] && ok "Discard test #7: PASSED [$res_errata_id]" || fatal "Discrad test #7: FALIED [discard errata]"

_updated=`curl -s -X 'POST' http://$HOSTIP:$TEST_PORT/discard?name=$errata_id_2` || fatal "Failed to get data from service"
res_errata_id=`echo $_updated | jq -r '.errata.id'`
[[ $res_errata_id == $errata_id_2 ]] && ok "Discard test #8: PASSED [$res_errata_id]" || fatal "Discrad test #7: FALIED [discard errata]"

_updated=`curl -s -X 'POST' http://$HOSTIP:$TEST_PORT/discard?name=$errata_id_3` || fatal "Failed to get data from service"
res_errata_id=`echo $_updated | jq -r '.errata.id'`
[[ $res_errata_id == $errata_id_3 ]] && ok "Discard test #9: PASSED [$res_errata_id]" || fatal "Discrad test #7: FALIED [discard errata]"

_updated=`curl -s -X 'POST' http://$HOSTIP:$TEST_PORT/discard?name=$errata_id_3` || fatal "Failed to get data from service"
res_errata_id=`echo $_updated | jq -r '.errata.id'`
[[ -z "$new_errata_id" ]] && ok "Discard test #10: PASSED" || fatal "Discrad test #7: FALIED [discard errata]"


# clean-up
clean_up
exit 0
