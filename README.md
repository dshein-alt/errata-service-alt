# ALT Errata Service

## Overview
The project is a service for creating and updating errata for ALT Linux. It provides three methods:  
- Generate errata - this method allows to generate errata with a unique id by prefix (a unique id is generated by 
 sha1("PREFIX-NUM"), where prefix is the input parameter to the service, and num is a unique number(num=lust_num+1)) 
and writes to the database and then return to client, 
- Update errata - this method allows you to update the number of errata updates by the errata number, 
- Check errata - this method checks for errata

## API ENDPOINT
- GET /register?prefix=PREFIX
- POST /update?name=NAME
- GET /check?name=NAME

Possible responses: 
- 200(ok), 
- 405(use not allowed method), 
- 400(request parse error), 
- 500(connect to clickhouse fail), 404(db error)

## Project structure
```
|-- cmd // folder with entry point(main.go)
|-- pkg- // folder with pkg, that are used in the project
|   |-- configurator // pkg for parsing flags, and config file
|   |-- logger // pkg for logging
|   |-- server // main pkg for API 
|   |-- service // layer between api and db
|   |-- db // pkg for database manipulation
```
## Config
Example config file is located on ./config/config.yml.example, change it and rename to config.yml

Fields:
- database - clickhouse database name
- login - clickhouse database login
- password - clickhouse database password
- clickhouse_address 
- dialTimeout - timeout for establishing new connections
- HTTP - use HTTP to connect to db
- allowed - allowed address

## Install
Along the path ./config/errata.sql there is sql file with table that must be in clickhouse for the service to work correctly
### Local
Use 
```
go build -o build/service cmd/main.go
```
Then correct config file and run service 
```
./build/service -c config/config.yml
```
### Docker-Compose
Use
```
docker-compose up 
```

if you received access denied, check container console and add your compose gateway in config/config.yml

## Test
Use errata.http in ./api_test to test how it works

## Response
This response comes from the server to the request
```
{
"comment": string
"errata": {
     "id": string
     "created":string
     "changed":string
    }
}
```
