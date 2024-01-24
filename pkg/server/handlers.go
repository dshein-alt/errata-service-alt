package server

import (
	"errataService/pkg/service"
	"net/http"
)

func registerHandler(w http.ResponseWriter, r *http.Request) {
	if !accessAddress(w, r) {
		return
	}
	if r.Method == http.MethodGet {
		prefix, year, s, err := parseRegisterQuery(r)
		if err != nil {
			errorLogger.Printf(err.Error())
			err = sendAnswer(w, s, "wrong request", nil)
			if err != nil {
				errorLogger.Printf(err.Error())
			}
			return
		}
		errata, s, err := service.Service.GenerateErrata(prefix, year)
		if err != nil {
			errorLogger.Printf(err.Error())
			err = sendAnswer(w, s, "generate error", nil)
			if err != nil {
				errorLogger.Printf(err.Error())
			}
			return
		}
		err = sendAnswer(w, s, "OK", errata)
		if err != nil {
			errorLogger.Printf(err.Error())
			return
		}
	} else {
		err := sendAnswer(w, http.StatusMethodNotAllowed, "", nil)
		if err != nil {
			errorLogger.Println(err.Error())
			return
		}
	}
}

func updateHandler(w http.ResponseWriter, r *http.Request) {
	if !accessAddress(w, r) {
		return
	}
	if r.Method == http.MethodPost {
		name, s, err := parseQuery(r)
		if err != nil {
			errorLogger.Printf(err.Error())
			err = sendAnswer(w, s, "wrong request", nil)
			if err != nil {
				errorLogger.Printf(err.Error())
			}
			return
		}
		errata, s, err := service.Service.UpdateErrata(name)
		if err != nil {
			errorLogger.Printf(err.Error())
			if err.Error() == "sql: no rows in result set" {
				err = sendAnswer(w, http.StatusNotFound, "not found", nil)
			} else {
				err = sendAnswer(w, s, "update error", nil)
			}
			if err != nil {
				errorLogger.Printf(err.Error())
			}
			return
		}
		err = sendAnswer(w, s, "OK", errata)
		if err != nil {
			errorLogger.Printf(err.Error())
			return
		}
	} else {
		err := sendAnswer(w, http.StatusMethodNotAllowed, "", nil)
		if err != nil {
			errorLogger.Println(err.Error())
			return
		}
	}
}

func checkHandler(w http.ResponseWriter, r *http.Request) {
	if !accessAddress(w, r) {
		return
	}
	if r.Method == http.MethodGet {
		name, s, err := parseQuery(r)
		if err != nil {
			errorLogger.Printf(err.Error())
			err = sendAnswer(w, s, "wrong request", nil)
			if err != nil {
				errorLogger.Printf(err.Error())
			}
			return
		}
		errata, s, err := service.Service.GetErrata(name)
		if err != nil {
			errorLogger.Printf(err.Error())
			if err.Error() == "sql: no rows in result set" {
				err = sendAnswer(w, http.StatusNotFound, "not found", nil)
			} else {
				err = sendAnswer(w, s, "check error", nil)
			}
			if err != nil {
				errorLogger.Printf(err.Error())
			}
			return
		}
		err = sendAnswer(w, s, "OK", errata)
		if err != nil {
			errorLogger.Printf(err.Error())
			return
		}
	} else {
		err := sendAnswer(w, http.StatusMethodNotAllowed, "", nil)
		if err != nil {
			errorLogger.Println(err.Error())
			return
		}
	}
}

func discardHandler(w http.ResponseWriter, r *http.Request) {
	if !accessAddress(w, r) {
		return
	}
	if r.Method == http.MethodPost {
		name, s, err := parseQuery(r)
		if err != nil {
			errorLogger.Printf(err.Error())
			err = sendAnswer(w, s, "wrong request", nil)
			if err != nil {
				errorLogger.Printf(err.Error())
			}
			return
		}
		errata, s, err := service.Service.DeleteErrata(name)
		if err != nil {
			errorLogger.Printf(err.Error())
			if err.Error() == "sql: no rows in result set" {
				err = sendAnswer(w, http.StatusNotFound, "not found", nil)
			} else {
				err = sendAnswer(w, s, "check error", nil)
			}
			if err != nil {
				errorLogger.Printf(err.Error())
			}
			return
		}
		err = sendAnswer(w, s, "OK", errata)
		if err != nil {
			errorLogger.Printf(err.Error())
			return
		}
	} else {
		err := sendAnswer(w, http.StatusMethodNotAllowed, "", nil)
		if err != nil {
			errorLogger.Println(err.Error())
			return
		}
	}
}
