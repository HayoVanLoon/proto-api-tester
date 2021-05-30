package main

import (
	"encoding/json"
	"fmt"
	h2 "github.com/HayoVanLoon/go-commons/http"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/descriptorpb"
	"io/ioutil"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"

	"github.com/rs/cors"
)

var fileDescriptorSet *descriptorpb.FileDescriptorSet
var messages map[string]*descriptorpb.DescriptorProto
var services map[string]*descriptorpb.ServiceDescriptorProto

type msgComment struct {
	Fields map[string]string
}

type svcComment struct {
	Methods map[string]string
}

var comments map[string]string

func handleGetMessage(w http.ResponseWriter, r *http.Request) {
	xs := strings.Split(r.URL.Path, "/")
	if len(xs) != 3 {
		http.NotFound(w, r)
		return
	}
	clean := strings.TrimLeft(xs[2], ".")
	m, ok := messages[clean]
	if !ok {
		log.Printf("could not find %s", clean)
		http.NotFound(w, r)
		return
	}
	writeOk(w, m)
}

func handleGetService(w http.ResponseWriter, r *http.Request) {
	xs := strings.Split(r.URL.Path, "/")
	if len(xs) != 3 {
		http.NotFound(w, r)
		return
	}
	svc, ok := services[xs[2]]
	if !ok {
		log.Printf("could not find %s", xs[2])
		http.NotFound(w, r)
		return
	}
	writeOk(w, svc)
}

func handleGetComment(w http.ResponseWriter, r *http.Request) {
	xs := strings.Split(r.URL.Path, "/")
	if len(xs) != 3 {
		http.NotFound(w, r)
		return
	}
	c, ok := comments[xs[2]]
	if !ok {
		//log.Printf("could not find %s", xs[2])
		//http.NotFound(w, r)
		//return
		c = ""
	}
	comment := struct {
		Text string `json:"text"`
	}{c}
	bs, _ := json.Marshal(comment)
	w.Header().Set("content-type", "application/json")
	_, _ = w.Write(bs)
}

func handleGetSettings(w http.ResponseWriter, r *http.Request) {
	var names []string
	for s := range services {
		names = append(names, s)
	}
	x := struct {
		Services          []string                        `json:"services"`
		GatewayUrl        string                          `json:"gatewayUrl"`
		FileDescriptorSet *descriptorpb.FileDescriptorSet `json:"file_descriptor_set"`
	}{
		Services:          names,
		GatewayUrl:        "localhost:8080",
		FileDescriptorSet: fileDescriptorSet,
	}
	bs, _ := json.Marshal(x)
	w.Header().Set("content-type", "application/json")
	_, _ = w.Write(bs)
}

func writeOk(w http.ResponseWriter, m proto.Message) {
	bs, _ := protojson.Marshal(m)
	_, _ = w.Write(bs)
}

func readApiDescriptor(path string) (*descriptorpb.FileDescriptorSet, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	bs, err := ioutil.ReadAll(f)
	if err != nil {
		return nil, err
	}
	m := &descriptorpb.FileDescriptorSet{}
	if err := proto.Unmarshal(bs, m); err != nil {
		return nil, err
	}
	return m, nil
}

func resolveNested(parent string, d *descriptorpb.DescriptorProto) {
	for _, nested := range d.NestedType {
		key := fmt.Sprintf("%s.%s", parent, nested.GetName())
		messages[key] = nested
		resolveNested(key, nested)
	}
}

func initMaps() error {
	messages = make(map[string]*descriptorpb.DescriptorProto)
	services = make(map[string]*descriptorpb.ServiceDescriptorProto)
	comments = make(map[string]string)

	for _, fd := range fileDescriptorSet.File {
		pkg := fd.GetPackage()
		for _, svc := range fd.Service {
			key := fmt.Sprintf("%s.%s", pkg, svc.GetName())
			services[key] = svc
		}
		for _, msg := range fd.MessageType {
			key := fmt.Sprintf("%s.%s", pkg, msg.GetName())
			messages[key] = msg
			resolveNested(key, msg)
		}
		for _, l := range fd.SourceCodeInfo.GetLocation() {
			if l.LeadingComments != nil {
				name, typ := getNameFromFileDescriptor(fd, l.Path, 0)
				comments[strings.Join(name, ".")] = l.GetLeadingComments()
				fmt.Printf("%s %s: %s", typ, name, *l.LeadingComments)
			}
		}
	}
	return nil
}

// TODO(hvl): find out where to find these numbers via reflect
const (
	numberFileDescriptorMessageType = 4
	numberFileDescriptorService     = 6
	numberDescriptorNestedType      = 3
	numberDescriptorField           = 2
	numberServiceDescriptorMethod   = 2
)

func getNameFromFileDescriptor(fd *descriptorpb.FileDescriptorProto, path []int32, idx int) ([]string, string) {
	names := []string{fd.GetPackage()}
	typ := "message"
	if len(path) > idx {
		var xs []string
		if path[0] == numberFileDescriptorMessageType {
			xs, typ = getNameFromDescriptor(fd.MessageType[path[idx+1]], path, idx+2)
			names = append(names, xs...)
		} else if path[0] == numberFileDescriptorService {
			xs, typ = getNameFromServiceDescriptor(fd.GetService()[path[idx+1]], path, idx+2)
			names = append(names, xs...)
		} else {
			names = append(names, fmt.Sprintf("path:%v", path))
			typ = "!!unsupported!!"
		}
	}
	return names, typ
}

func getNameFromDescriptor(d *descriptorpb.DescriptorProto, path []int32, idx int) ([]string, string) {
	names := []string{d.GetName()}
	typ := "message"
	if len(path) > idx {
		var xs []string
		if path[idx] == numberDescriptorNestedType {
			xs, typ = getNameFromDescriptor(d.GetNestedType()[path[idx+1]], path, idx+2)
			names = append(names, xs...)
		} else if path[idx] == numberDescriptorField {
			xs, typ = getNameFromFieldDescriptor(d.GetField()[path[idx+1]], path, idx+2)
			names = append(names, xs...)
		} else {
			names = append(names, fmt.Sprintf("path:%v", path[idx:]))
			typ = "!!unsupported!!"
		}
	}
	return names, typ
}

func getNameFromFieldDescriptor(d *descriptorpb.FieldDescriptorProto, path []int32, idx int) ([]string, string) {
	xs := []string{d.GetName()}
	typ := "field"
	if len(path) > idx {
		xs = append(xs, fmt.Sprintf("path:%v", path[idx:]))
	}
	return xs, typ
}

func getNameFromServiceDescriptor(d *descriptorpb.ServiceDescriptorProto, path []int32, idx int) ([]string, string) {
	names := []string{d.GetName()}
	typ := "service"
	if len(path) > idx {
		var xs []string
		if path[idx] == numberServiceDescriptorMethod {
			xs, typ = getNameFromMethodDescriptor(d.GetMethod()[path[idx+1]], path, idx+2)
			names = append(names, xs...)
		} else {
			names = append(names, fmt.Sprintf("path:%v", path[idx:]))
			typ = "!!unsupported!!"
		}
	}
	return names, typ
}

func getNameFromMethodDescriptor(d *descriptorpb.MethodDescriptorProto, path []int32, idx int) ([]string, string) {
	xs := []string{d.GetName()}
	typ := "method"
	if len(path) > idx {
		xs = append(xs, fmt.Sprintf("path:%v", path[idx:]))
		typ = "!!unsupported!!"
	}
	return xs, typ
}

func echo(fn http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		log.Printf("%s %s", r.Method, r.URL)
		fn(w, r)
	}
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	var err error
	fileDescriptorSet, err = readApiDescriptor("./api_descriptor.pb")
	if err != nil {
		log.Fatalf("error: %s", err)
	}
	err = initMaps()
	if err != nil {
		log.Fatalf("error: %s", err)
	}

	c := cors.New(cors.Options{
		AllowOriginFunc: func(origin string) bool {
			u, err := url.Parse(origin)
			if err != nil {
				return false
			}
			return strings.HasPrefix(u.Host, "localhost")
		},
		AllowedMethods: []string{
			http.MethodHead,
			http.MethodGet,
			http.MethodPost,
			http.MethodPut,
			http.MethodPatch,
			http.MethodDelete,
		},
		AllowedHeaders:   []string{"*"},
		AllowCredentials: true,
	})

	mux := h2.NewTreeMux()
	mux.HandleFunc("/comments/*", echo(handleGetComment))
	mux.HandleFunc("/messages/*", echo(handleGetMessage))
	mux.HandleFunc("/services/*", echo(handleGetService))
	mux.HandleFunc("/settings", echo(handleGetSettings))

	if err := http.ListenAndServe(":"+port, c.Handler(mux)); err != nil {
		log.Fatalf("error %s", err)
	}
}
