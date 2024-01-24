package db

import (
	"errataService/pkg/configurator"
	"errataService/pkg/utils"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"github.com/ClickHouse/clickhouse-go/v2"
)

var tableName string

func InitDB() (*DB, error) {
	opt := clickhouse.Options{
		Addr: []string{configurator.Config.AddressToClick},
		Auth: clickhouse.Auth{
			Database: configurator.Config.DataBase,
			Username: configurator.Config.Login,
			Password: configurator.Config.Password,
		},
		Settings: clickhouse.Settings{
			"max_execution_time": 60,
		},
		DialTimeout: time.Duration(configurator.Config.DialTimeout) * time.Second,
		Compression: &clickhouse.Compression{
			Method: clickhouse.CompressionLZ4,
		},
	}
	if configurator.Config.HTTP {
		opt.Protocol = clickhouse.HTTP
	}
	conn := clickhouse.OpenDB(&opt)
	ping := conn.Ping()
	if ping != nil {
		return nil, ping
	}
	dataBase := DB{
		db: conn,
	}
	tableName = configurator.Config.TableName
	return &dataBase, nil
}

func (db *DB) CheckConnect() bool {
	status := db.db.Ping()
	return status == nil
}

func (db *DB) GetErrata(errata_id string) (*Errata, int, error) {
	db.mtx.Lock()
	defer db.mtx.Unlock()
	var errata Errata
	row := db.db.QueryRow(fmt.Sprintf("SELECT * FROM %s WHERE errata_id = $1 AND errata_update_count = (SELECT max(errata_update_count) FROM %s WHERE errata_id= $1)", tableName, tableName), errata_id)
	if err := row.Scan(&errata.id, &errata.Prefix, &errata.Year, &errata.Num, &errata.UpdateCount, &errata.CreationDate, &errata.ChangeDate); err != nil {
		return nil, http.StatusNotFound, err
	}
	return &errata, http.StatusOK, nil
}

func (db *DB) UpdateErrata(errata_id string, update uint32) (*Errata, int, error) {
	db.mtx.Lock()
	defer db.mtx.Unlock()
	var errata Errata
	row := db.db.QueryRow(fmt.Sprintf("SELECT * FROM %s WHERE errata_id = $1 AND errata_update_count = (SELECT max(errata_update_count) FROM %s WHERE errata_id= $1)", tableName, tableName), errata_id)
	if err := row.Scan(&errata.id, &errata.Prefix, &errata.Year, &errata.Num, &errata.UpdateCount, &errata.CreationDate, &errata.ChangeDate); err != nil {
		return nil, http.StatusNotFound, err
	}
	if errata.UpdateCount != update {
		return nil, http.StatusNotFound, errors.New("version doesn`t match")
	}
	errata.UpdateCount += 1
	errata.ChangeDate = time.Now()
	_, err := db.db.Exec(fmt.Sprintf("INSERT INTO %s VALUES ($1, $2, $3, $4, $5, $6, $7)", tableName),
		errata.id, errata.Prefix, errata.Year, errata.Num,
		errata.UpdateCount, errata.CreationDate, errata.ChangeDate)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return &errata, http.StatusOK, nil
}

func (db *DB) GenerateErrata(prefix string, year uint32) (*Errata, int, error) {
	db.mtx.Lock()
	defer db.mtx.Unlock()
	var last uint32
	var current uint32
	row := db.db.QueryRow(fmt.Sprintf("SELECT max(errata_num) FROM %s WHERE errata_year = $1", tableName), year)
	if err := row.Scan(&last); err != nil {
		return nil, http.StatusNotFound, err
	}
	if last < 999 {
		last = 999
	}
	current = last + 1
	id := utils.SHA1(prefix + "-" + strconv.FormatUint(uint64(year), 10) + "-" + strconv.FormatUint(uint64(current), 10))
	errata := CreateErrata(id, prefix, year, current, 1, time.Now(), time.Now())
	_, err := db.db.Exec(fmt.Sprintf("INSERT INTO %s VALUES ($1, $2, $3, $4, $5, $6, $7)", tableName),
		errata.id, errata.Prefix, errata.Year, errata.Num,
		errata.UpdateCount, errata.CreationDate, errata.ChangeDate)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return errata, http.StatusOK, nil
}

func (db *DB) DeleteErrata(errata_id string, update uint32) (*Errata, int, error) {
	db.mtx.Lock()
	defer db.mtx.Unlock()
	var errata Errata
	row := db.db.QueryRow(fmt.Sprintf("SELECT * FROM %s WHERE errata_id = $1 AND errata_update_count = (SELECT max(errata_update_count) FROM %s WHERE errata_id= $1)", tableName, tableName), errata_id)
	if err := row.Scan(&errata.id, &errata.Prefix, &errata.Year, &errata.Num, &errata.UpdateCount, &errata.CreationDate, &errata.ChangeDate); err != nil {
		return nil, http.StatusNotFound, err
	}
	if errata.UpdateCount != update {
		return nil, http.StatusNotFound, errors.New("version doesn`t match")
	}
	_, err := db.db.Exec(fmt.Sprintf("DELETE FROM %s WHERE errata_id = $1 AND errata_update_count = $2", tableName), errata.id, errata.UpdateCount)
	if err != nil {
		return nil, http.StatusInternalServerError, err
	}
	return &errata, http.StatusOK, nil
}

func (db *DB) Close() {
	db.db.Close()
}
