---
layout: post
title: From Docker to Kubernetes
---

## Prologue

I used to be confused about Kubernetes. I still am, but I used to, too.

## Requirements

Please have the following installed on your local development machine:

1. `docker`

2. `minikube`

3. `kubectl`

This tutorial expects you to understand a little about Docker and very little about Kubernetes.

## Things to mention in order

{% highlight javascript %}
var http = require('http');

var server = http.createServer(function(req, res) {
  res.writeHead(200, {'Content-Type': 'text/plain'});
  res.end('Hello world\n');
});

server.listen(8888);
{% endhighlight %}

`node index.js`

{% highlight docker %}
FROM node

RUN mkdir -p /usr/src/app

WORKDIR /usr/src/app

COPY index.js /usr/src/app/index.js

EXPOSE 8888

CMD ["node", "index.js"]
{% endhighlight %}

`docker build -t yefim/hello-node .`

`docker run -p 8888:8888 yefim/hello-node`

`docker push yefim/hello-node`

`minikube start`

`kubectl run hello-node --image="yefim/hello-node"`

`kubectl get deployments`

`kubectl get pods`

`kubectl expose deployment hello-node --port 8888`

`kubectl get services`

`kubectl edit services hello-node`

`kubectl get services`

`minikube ip`

{% highlight javascript %}
var http = require('http');
var os = require('os'); // FRESH

var server = http.createServer(function(req, res) {
  res.writeHead(200, {'Content-Type': 'text/plain'});
  res.end(os.hostname() + '\n'); // FRESH
});

server.listen(8888);
{% endhighlight %}
