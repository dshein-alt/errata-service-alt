package service

import (
	"errataService/pkg/db"
	"errors"
	"net/http"
	"time"
)

func (service *ServiceT) GenerateErrata(prefix string, year uint32) (*db.Errata, int, error) {
	status := service.db.CheckConnect()
	if !status {
		time.Sleep(time.Second)
		err := service.tryConnect()
		if err != nil {
			return nil, http.StatusInternalServerError, err
		}
		status = service.db.CheckConnect()
		if !status {
			return nil, http.StatusInternalServerError, errors.New("connection to the database failed")
		}
	}
	return service.db.GenerateErrata(prefix, year)
}

func (service *ServiceT) GetErrata(errata string) (*db.Errata, int, error) {
	status := service.db.CheckConnect()
	if !status {
		time.Sleep(time.Second)
		err := service.tryConnect()
		if err != nil {
			return nil, http.StatusInternalServerError, err
		}
		status = service.db.CheckConnect()
		if !status {
			return nil, http.StatusInternalServerError, errors.New("connection to the database failed")
		}
	}

	errata_id, _, err := db.ErrataToID(errata)
	if err != nil {
		return nil, http.StatusBadRequest, err
	}
	return service.db.GetErrata(errata_id)
}

func (service *ServiceT) UpdateErrata(errata string) (*db.Errata, int, error) {
	status := service.db.CheckConnect()
	if !status {
		time.Sleep(time.Second)
		err := service.tryConnect()
		if err != nil {
			return nil, http.StatusInternalServerError, err
		}
		status = service.db.CheckConnect()
		if !status {
			return nil, http.StatusInternalServerError, errors.New("connection to the database failed")
		}
	}

	errata_id, update, err := db.ErrataToID(errata)
	if err != nil {
		return nil, http.StatusBadRequest, err
	}
	return service.db.UpdateErrata(errata_id, update)
}

func (service *ServiceT) DeleteErrata(errata string) (*db.Errata, int, error) {
	status := service.db.CheckConnect()
	if !status {
		time.Sleep(time.Second)
		err := service.tryConnect()
		if err != nil {
			return nil, http.StatusInternalServerError, err
		}
		status = service.db.CheckConnect()
		if !status {
			return nil, http.StatusInternalServerError, errors.New("connection to the database failed")
		}
	}

	errata_id, update, err := db.ErrataToID(errata)
	if err != nil {
		return nil, http.StatusBadRequest, err
	}
	return service.db.DeleteErrata(errata_id, update)
}

func (service *ServiceT) CloseConnect() {
	service.db.Close()
}

func (service *ServiceT) tryConnect() error {
	conn, err := db.InitDB()
	if err != nil {
		return err
	}
	service.db = conn
	return nil
}
