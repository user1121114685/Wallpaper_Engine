package main

import (
	"C"
	"bytes"
	"context"
	"github.com/gogf/gf/encoding/gjson"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"strings"

	"github.com/chromedp/cdproto/network"
	"github.com/chromedp/chromedp"
	"github.com/gogf/gf/text/gregex"
)

func main() {
	// http.HandleFunc("/api", apiHandler)
	// http.ListenAndServe(":9191", nil)
	//  go build  -ldflags="-H windowsgui"
	// go build -buildmode=c-shared -o ../../assets/steamdownload.dll
}

// func apiHandler(w http.ResponseWriter, r *http.Request) {
// 	api := getAPI()
// 	fmt.Fprintf(w, api)
// }

//export GetUUID
func GetUUID(url *C.char,fileid *C.char)*C.char{
	rawStr :="{\"publishedFileId\":"+fileid+",\"collectionId\":null,\"hidden\":false,\"downloadFormat\":\"raw\",\"autodownload\":false}"
	resp,err:=http.Post(url,"application/x-www-form-urlencoded",bytes.NewBuffer([]byte(rawStr)))
	defer resp.Body.Close()
	if err != nil {
		return C.CString("error")
	}
	s, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return C.CString("error")
	}
	var uuid string
	if j, err := gjson.DecodeToJson(string(s)); err != nil {
		return C.CString("error")
	} else {
		uuid = j.GetString("uuid")
	}
	return C.CString(uuid)
}

//export GetAPI
func GetAPI() *C.char { // 导出的函数要首字大写 getAPI是错的 并且还需加上注释 //export GetAPI

	// 浏览主页 获取api
	var apiUrl string
	dir, err := ioutil.TempDir("", "chromedp-we")
	if err != nil {
		panic(err)
	}
	defer os.RemoveAll(dir)

	opts := append(chromedp.DefaultExecAllocatorOptions[:],
		chromedp.DisableGPU,
		chromedp.NoDefaultBrowserCheck,
		chromedp.Flag("headless", true),
		chromedp.Flag("ignore-certificate-errors", true),
		chromedp.Flag("window-size", "400,400"),
		chromedp.UserDataDir(dir),
	)

	allocCtx, cancel := chromedp.NewExecAllocator(context.Background(), opts...)
	defer cancel()

	// also set up a custom logger
	taskCtx, cancel := chromedp.NewContext(allocCtx, chromedp.WithLogf(log.Printf))
	defer cancel()

	// ensure that the browser process is started
	if err := chromedp.Run(taskCtx); err != nil {
		return C.CString("未安装Chrome")
	}
	//listenForNetworkEvent(taskCtx)

	chromedp.ListenTarget(taskCtx, func(ev interface{}) {

		switch ev := ev.(type) {

		case *network.EventResponseReceived:
			resp := ev.Response
			if len(resp.Headers) != 0 {
				// log.Printf("received headers: %s", resp.Headers)

				if strings.Index(resp.URL, "/download/status") != -1 {

					RespURL, err := gregex.MatchString(`https://.+/api/`, resp.URL)
					if err == nil {
						apiUrl = RespURL[0]
					} else {

						apiUrl = "ApiFailed"
					}
					// 等待几秒，也算是支持了作者，不至于被白嫖而不堪重负

					// go func() {
					// 	time.Sleep(time.Second * 5)
					// 	cancel()
					// }()
					cancel()

				}
			}

		}
		// other needed network Event
	})
	chromedp.Run(taskCtx,
		network.Enable(),
		chromedp.Navigate(`https://steamworkshopdownloader.io/`),
		chromedp.WaitVisible(`body`, chromedp.BySearch),
	)
	return C.CString(apiUrl)

}

