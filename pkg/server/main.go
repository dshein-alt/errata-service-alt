package server

import (
	"errataService/pkg/configurator"
	"errataService/pkg/logger"
	"errataService/pkg/service"
	"fmt"
	"net/http"
)

var infoLogger = logger.NewLogger("INFO")
var errorLogger = logger.NewLogger("ERROR")

func Run() error {
	err := service.CreateService()
	if err != nil {
		return err
	}
	defer service.Service.CloseConnect()

	http.HandleFunc("/register", registerHandler)
	http.HandleFunc("/update", updateHandler)
	http.HandleFunc("/check", checkHandler)
	http.HandleFunc("/discard", discardHandler)
	http.HandleFunc("/version", versionHandler)

	infoLogger.Printf("Service '%s' started at %d", configurator.Config.Name, configurator.Config.Port)
	addr := fmt.Sprintf(":%d", configurator.Config.Port)
	err = http.ListenAndServe(addr, nil)
	if err != nil {
		return err
	}
	return nil
}
