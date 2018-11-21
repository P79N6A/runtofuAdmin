package main

import (
	"flag"
	"fmt"
	"git.xiaojukeji.com/soda-framework/go-log"
	"git.xiaojukeji.com/soda-framework/go-thrift/server"
	"git.xiaojukeji.com/trade-engine/search-broker-idl/gen/go/searchbroker"
	"git.xiaojukeji.com/trade-engine/search-broker/client-manager"
	"git.xiaojukeji.com/trade-engine/search-broker/common/apollo"
	"git.xiaojukeji.com/trade-engine/search-broker/common/bi-log"
	"git.xiaojukeji.com/trade-engine/search-broker/common/config"
	"git.xiaojukeji.com/trade-engine/search-broker/common/gc-monitor"
	"git.xiaojukeji.com/trade-engine/search-broker/common/localcache"
	"git.xiaojukeji.com/trade-engine/search-broker/common/mapping-file"
	"git.xiaojukeji.com/trade-engine/search-broker/service"
	"net/http"
	"runtime"
	"runtime/debug"
	"strconv"
	"time"
)

const (
	GcMonitorPeriod = 10 // Second
)

func main() {
	defer func() {
		if err := recover(); err != nil {
			log.Errorf("catch panic %v", err)
			return
		}
	}()

	var configPath string
	// para1: file handle para2: CLI para name para3: default value para4: desc info
	flag.StringVar(&configPath, "config", "conf/service.conf", "server config.")
	flag.Parse()
	// parse config
	if err := config.Init(configPath); err != nil {
		fmt.Printf("fail to read config.||err=%v||config=%v ", err, configPath)
		//os.Exit(1)
		return
	}
	config.PrintParameterConfig()
	conf := config.GetConfig()
	// init log
	log.Init(&conf.Log)
	defer log.Close()
	log.Debugf("config=[%v]", conf)

	//init gc percent
	log.Infof("set gc percent:%v", config.GetGcPercent())
	debug.SetGCPercent(config.GetGcPercent())

	//gc monitor
	if conf.GCMonitor.IsOpen {
		// goroutine stats and pprof
		go func() {
			http.HandleFunc("/goroutines", func(w http.ResponseWriter, r *http.Request) {
				num := strconv.FormatInt(int64(runtime.NumGoroutine()), 10)
				w.Write([]byte(num + "\n"))
			})
			err := http.ListenAndServe(conf.GCMonitor.Addr, nil)
			if err != nil {
				log.Errorf("goroutine stats and pprof listen on %s error:%v", conf.GCMonitor.Addr, err)
				return
			}
			log.Info("goroutine stats and pprof listen on %s", conf.GCMonitor.Addr)
		}()
	}
	//untime.MemStats
	go func() {
		t1 := time.NewTicker(GcMonitorPeriod * time.Second)
		for {
			select {
			case <-t1.C:
				gc_monitor.PrintGCSummary()
			}
		}
	}()

	bi_log.InitBiLogger(conf.Log.FilePath)
	// init localcache
	localcache.SetLocalCacheOpen(true, config.GetLocalCacheMaxMemorySize())
	log.Infof("localcache init succeed")
	err := mapping_file.LoadMappingFile("conf/mappingtable.csv")
	if err != nil {
		log.Errorf("mappingfile init failed")
		//os.Exit(1)
		return
	}

	err = client_manager.Init(conf)
	if err != nil {
		log.Errorf("init client manager failed")
		//os.Exit(1)
		return
	}
	log.Infof("client init succeed")

	apollo.InitApollo()
	defer apollo.CloseApollo()

	// 启动服务。
	log.Debugf("before startThriftServer")
	startThriftServer(&conf.Server)
	log.Debugf("after startThriftServer")

}

func startThriftServer(config *server.Config) {
	handler := service.New()
	processor := searchbroker.NewSearchBrokerProcessor(handler)
	s := server.New(config)
	s.Serve(processor)
}
