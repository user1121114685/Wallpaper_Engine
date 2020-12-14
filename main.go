package main

import (
	"archive/zip"
	"bytes"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/dustin/go-humanize"
	"github.com/gogf/gf/encoding/gjson"
	"github.com/gogf/gf/text/gregex"
	"github.com/gogf/gf/text/gstr"
)

func UnZip(dst, src string) (err error) {
	// 打开压缩文件，这个 zip 包有个方便的 ReadCloser 类型
	// 这个里面有个方便的 OpenReader 函数，可以比 tar 的时候省去一个打开文件的步骤
	zr, err := zip.OpenReader(src)
	defer zr.Close()
	if err != nil {
		return
	}

	// 如果解压后不是放在当前目录就按照保存目录去创建目录
	if dst != "" {
		if err := os.MkdirAll(dst, 0755); err != nil {
			return err
		}
	}

	// 遍历 zr ，将文件写入到磁盘
	for _, file := range zr.File {
		path := filepath.Join(dst, file.Name)

		// 如果是目录，就创建目录
		if file.FileInfo().IsDir() {
			if err := os.MkdirAll(path, file.Mode()); err != nil {
				return err
			}
			// 因为是目录，跳过当前循环，因为后面都是文件的处理
			continue
		}

		// 获取到 Reader
		fr, err := file.Open()
		if err != nil {
			return err
		}

		// 创建要写出的文件对应的 Write
		fw, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR|os.O_TRUNC, file.Mode())
		if err != nil {
			return err
		}

		n, err := io.Copy(fw, fr)
		if err != nil {
			return err
		}

		// 将解压的结果输出
		fmt.Printf("成功解压 %s ，共写入了 %d 个字符的数据\n", path, n)

		// 因为是在循环中，无法使用 defer ，直接放在最后
		// 不过这样也有问题，当出现 err 的时候就不会执行这个了，
		// 可以把它单独放在一个函数中，这里是个实验，就这样了
		fw.Close()
		fr.Close()
	}
	return nil
}

// 下载进度
type WriteCounter struct {
	Total uint64
}

func (wc *WriteCounter) Write(p []byte) (int, error) {
	n := len(p)
	wc.Total += uint64(n)
	wc.PrintProgress()
	return n, nil
}

// 下载进度
func (wc WriteCounter) PrintProgress() {
	fmt.Printf("\r%s", strings.Repeat(" ", 35))
	fmt.Printf("\rDownloading... %s complete", humanize.Bytes(wc.Total))
}

func DownloadFile(filepath string, url string) error {
	out, err := os.Create(filepath + ".tmp")
	if err != nil {
		return err
	}
	resp, err := http.Get(url)
	if err != nil {
		out.Close()
		return err
	}
	defer resp.Body.Close()
	counter := &WriteCounter{}
	if _, err = io.Copy(out, io.TeeReader(resp.Body, counter)); err != nil {
		out.Close()
		return err
	}
	fmt.Print("\n")
	out.Close()
	if err = os.Rename(filepath+".tmp", filepath); err != nil {
		return err
	}
	return nil
}

// 下载及解压
func downloadAndUnzip(url string, fileID string) {

	fmt.Println("Download Started   " + url)

	err := DownloadFile("./"+fileID+".zip", url)
	if err != nil {
		panic(err)
	}

	fmt.Println("Download Finished    " + url)
	// 文件下载 后通过大小判断 是否失败
	fi, err := os.Stat("./" + fileID + ".zip")
	if err == nil {
		fmt.Println("下载的文件大小为 ：  ", fi.Size(), err)
	}
	var filesize string
	filesize = fmt.Sprint(fi.Size())
	if filesize < "10240" {
		log.Fatalln("文件下载出错，请重新下载.....")
		var exitScan string
		_, _ = fmt.Scan(&exitScan)
	}
	// 解压
	if err := UnZip("./projects/defaultprojects/"+fileID, "./"+fileID+".zip"); err != nil {
		log.Fatalln(err)
	}
	err = os.Remove("./" + fileID + ".zip") //删除残留 刚才下载并且解压的的zip

	if err != nil {
		log.Fatalln(err)
	}
}

// 下载及解压
func downloadAndUnzip2(url string, fileID string) {

	fmt.Println("Download Started   " + url)

	err := DownloadFile("./"+fileID, url)
	if err != nil {
		panic(err)
	}

	fmt.Println("Download Finished    " + url)
	// 文件下载 后通过大小判断 是否失败
	fi, err := os.Stat("./" + fileID)
	if err == nil {
		fmt.Println("下载的文件大小为 ：  ", fi.Size(), err)
	}

	filesize, _ := strconv.ParseInt(fmt.Sprint(fi.Size()), 10, 64)
	// progress, _ = strconv.ParseInt(j.GetString(uuid+".progress"), 10, 64)
	// 如果压缩包小于1M 就不解压
	if filesize < int64(10240) {
		log.Fatalln("文件下载出错（小于1M），请重新下载.....")
		var exitScan string
		_, _ = fmt.Scan(&exitScan)
	}

	// 解压
	if err := UnZip("./projects/defaultprojects", "./"+fileID); err != nil {
		log.Fatalln(err)
	}
	err = os.Remove("./" + fileID) //删除残留 刚才下载并且解压的的zip

	if err != nil {
		log.Fatalln(err)
	}
}

// func main2() {

// 	// //把post表单发送给目标服务器
// 	// res, err := http.PostForm("http://steamworkshop.download/online/steamonline.php", url.Values{
// 	// 	"item": {"1714478720"},
// 	// 	"app":  {"431960"},
// 	// })
// 	// https://steamcommunity.com/sharedfiles/filedetails/?id=2309314482&searchtext=
// 	// 判断是否在正确的文件夹下
// 	_, err := os.Lstat("./wallpaper64.exe")
// 	if err != nil {
// 		fmt.Println("当前目录下没有  wallpaper64.exe ，请将本程序放入 wallpaper64.exe 同目录下运行。")
// 		var exitScan string
// 		_, _ = fmt.Scan(&exitScan)
// 		os.Exit(1)
// 	}
// 	// 等待用户输入
// 	var Link string
// 	for {
// 		fmt.Println("请输入包含ID的连接：")
// 		//当程序只是到fmt.Scanln(&name)程序会停止执行等待用户输入
// 		fmt.Scanln(&Link)
// 		// Link = "https://steamcommunity.com/sharedfiles/filedetails/?id=2309314482&searchtext="
// 		if !gstr.ContainsI(Link, "https://") {
// 			fmt.Println("不是正确的https  ID连接，例如 https://steamcommunity.com/sharedfiles/filedetails/?id=2309314482")
// 			continue
// 		}
// 		if !gstr.ContainsI(Link, "?id=") {
// 			fmt.Println("连接不包含ID，例如 https://steamcommunity.com/sharedfiles/filedetails/?id=2309314482")
// 			continue
// 		}
// 		break
// 	}
// 	fileID, _ := gregex.MatchString(`id=\d+`, Link)
// 	fmt.Println(fileID[0])
// 	fileID, _ = gregex.MatchString(`\d+`, Link)
// 	fmt.Println(fileID[0])
// 	c := g.Client()
// 	c.SetHeaderRaw(`
// 			Accept:*/*
// 			DNT:1
// 			X-Requested-With:XMLHttpRequest
// 			User-Agent:Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/87.0.4280.88 Safari/537.36
// 			Origin:http://steamworkshop.download
// 			Accept-Language:zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7
// 			Connection:keep-alive
// 			Content-Type:application/x-www-form-urlencoded
// 			Content-Length:26
// 		`)
// 	c.SetHeader("Referer", "http://steamworkshop.download/download/view/"+fileID[0])
// 	r, e := c.Post("http://steamworkshop.download/online/steamonline.php", g.Map{
// 		"item": fileID[0],
// 		"app":  "431960",
// 	})
// 	if e != nil {
// 		panic(e)
// 	} else {
// 		fileDownload, _ := gregex.MatchString(`http://.+?\.zip`, r.ReadAllString())

// 		fmt.Println(fileDownload[0])

// 		fileName, _ := gregex.MatchString(`\d+\.zip`, fileDownload[0])
// 		fmt.Println(fileName[0])
// 		downloadAndUnzip2(fileDownload[0], fileName[0])
// 	}
// 	defer r.Close()
// 	// 等待用户关闭（输入）
// 	println("")
// 	println("")
// 	println("软件开源地址：https://github.com/user1121114685/Wallpaper_Engine")
// 	println("执行完毕........重启 Wallpaper Engine 可以看到刚才下载的壁纸.....")

// 	var exitScan string
// 	_, _ = fmt.Scan(&exitScan)
// }

func main() {

	// 判断是否在正确的文件夹下
	_, err := os.Lstat("./wallpaper64.exe")
	if err != nil {
		fmt.Println("当前目录下没有  wallpaper64.exe ，请将本程序放入 wallpaper64.exe 同目录下运行。")
		var exitScan string
		_, _ = fmt.Scan(&exitScan)
		os.Exit(1)
	}
	// 友情提示
	println("Wallpaper Engine资源位置 https://steamcommunity.com/app/431960/workshop/")
	println("下载网站 1 https://steamworkshopdownloader.io/")
	println("下载网站 2 http://steamworkshop.download")
	// 等待用户输入
	var Link string
	// for {
	// 	fmt.Println("请选择你的下载网站：")
	// 	//当程序只是到fmt.Scanln(&name)程序会停止执行等待用户输入
	// 	fmt.Scanln(&Link)
	// 	// Link = "https://steamcommunity.com/sharedfiles/filedetails/?id=2309314482&searchtext="
	// 	if Link == "2" {
	// 		main2()
	// 		continue
	// 	}
	// 	if Link == "1" {
	// 		break
	// 	}
	// 	fmt.Println("你就不能正常的选择一个下载网站吗？")
	// }

	for {
		fmt.Println("请输入包含ID的连接：")
		//当程序只是到fmt.Scanln(&name)程序会停止执行等待用户输入
		fmt.Scanln(&Link)
		// Link = "https://steamcommunity.com/sharedfiles/filedetails/?id=2087854115&searchtext="
		if !gstr.ContainsI(Link, "https://") {
			fmt.Println("不是正确的https  ID连接，例如 https://steamcommunity.com/sharedfiles/filedetails/?id=2309314482")
			continue
		}
		if !gstr.ContainsI(Link, "?id=") {
			fmt.Println("连接不包含ID，例如 https://steamcommunity.com/sharedfiles/filedetails/?id=2309314482")
			continue
		}
		break
	}
	fileID, _ := gregex.MatchString(`id=\d+`, Link)

	fileID, _ = gregex.MatchString(`\d+`, Link)
	fmt.Println("下载的连接的ID是" + fileID[0])
	rawStr := "{" + "\"publishedFileId\":" + fileID[0] + "," + "\"collectionId\":null,\"extract\":true,\"hidden\":false,\"direct\":false,\"autodownload\":false" + "}"
	var jsonStr = []byte(rawStr)
	r, e := http.NewRequest("POST", "https://api_02.steamworkshopdownloader.io/api/download/request", bytes.NewBuffer(jsonStr))

	client := &http.Client{}
	resp, err := client.Do(r)
	if err != nil {
		panic(err)
	}
	defer resp.Body.Close()

	if e != nil {
		panic(e)
	} else {
		// {"uuid":"734f5478-7b66-49df-a6a0-ddbdf4106d61"}

		s, _ := ioutil.ReadAll(resp.Body) //把  body 内容读入字符串 s
		fmt.Println(string(s))
		var uuid string
		if j, err := gjson.DecodeToJson(string(s)); err != nil {
			panic(err)
		} else {
			uuid = j.GetString("uuid")
		}
		// 判断是否完成 等进度是100 以上 200 这种才开始结束
		//https://api_01.steamworkshopdownloader.io/api/download/status
		// {"uuids":["6df0dc8a-4ccd-4fd2-8532-3c933df4dc80"]}
		var progress int64 = 0

		for progress < int64(150) {
			time.Sleep(time.Second * 1)
			rawStr = "{\"uuids\":[\"" + uuid + "\"]}"
			var jsonStr = []byte(rawStr)
			r, e = http.NewRequest("POST", "https://api_02.steamworkshopdownloader.io/api/download/status", bytes.NewBuffer(jsonStr))

			client = &http.Client{}

			resp, err := client.Do(r)
			if err != nil {
				panic(err)
			}
			defer resp.Body.Close()

			s, _ = ioutil.ReadAll(resp.Body) //把  body 内容读入字符串 s
			fmt.Println(string(s))

			if j, err := gjson.DecodeToJson(string(s)); err != nil {
				panic(err)
			} else {
				progress, _ = strconv.ParseInt(j.GetString(uuid+".progress"), 10, 64)

			}
			fmt.Println("服务器下载进度    " + strconv.FormatInt(progress, 10))
		}
		fileDownload := "https://api_02.steamworkshopdownloader.io/api/download/transmit?uuid=" + uuid

		downloadAndUnzip(fileDownload, fileID[0])
	}
	// 等待用户关闭（输入）
	println("")
	println("")
	println("软件开源地址：https://github.com/user1121114685/Wallpaper_Engine")
	println("执行完毕........重启 Wallpaper Engine 可以看到刚才下载的壁纸.....")

	var exitScan string
	_, _ = fmt.Scan(&exitScan)
}
