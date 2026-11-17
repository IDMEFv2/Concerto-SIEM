# S4S Prototype and Kubernetes

All container are available thought kubernetes.

To do this we follow this workflow:
* Configure github actions into
  [IDMEFv2-Prototype repository](https://github.com/IDMEFv2/IDMEFv2-prototype) to
  automatically build containers for each functions. The github action is available here:
  [build.yml](https://github.com/IDMEFv2/IDMEFv2-prototype/blob/main/.github/workflows/build.yml)
  * Containers goes to
    [Docker Hub IDMEFv2 prototype repository](https://hub.docker.com/u/idmefv2prototype)
* Add Yaml Kubernetes Deployment configurations files into IDMEFv2-Prototype repository
  * Files are available in the
    [pods](https://github.com/IDMEFv2/IDMEFv2-prototype/tree/main/pods) folder,
    you just need to "apply" them.

By default, we supposed that you have At least 10Go of RAM so we can provide
4Go to Elasticsearch, 4Go to Logstash and the rest for other containers. You
can change this by manipulating Yaml files `elasticsearch.yml` and
`logstash.yml`. 

## Kubernetes services

The Yaml we provides create these services:
* Cluster internal services
  * Kafka
    * 9092, 19092, 29092: Kafka consumer/producer connexion
    * 9999: Kafka internal port
  * PostgreSQL
    * 5432: PostgreSQL database interface
  * Kafdrop
    * 9201: Kafdrop web interface
  * Elasticsearch
    * 9200: Elasticsearch API inteface
    * 9300: Elasticsearch internal port
  * Logstash
    * 6514 (TCP, UDP): Logstash syslog collect interface
    * 4690: Logstash IDMEFv2 collect interface
  * GUI
    * 8000: S4S Prototype web interface

* Exposed service on Kubernetes node
  * Kafdrop
    * 30192: Kafdrop web interface
  * ELasticsearch
    * 30292: Elasticsearch API inteface
  * Logstash
    * 30514 (TCP, UDP): Logstash syslog collect interface
  * GUI
    * 30080: : S4S Prototype web interface

## Access your S4S prototype

Simply go to `http://<node-ip>:30080`

## Send logs to S4S prototype

Configure your syslogs clients to send logs to `<node-ip>:30514`

## Debug S4S prototype

Try things like:
* Access logs of your kubernetes pods with `kubectl` [Official documentation](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_logs/)
* Access Kafdrop to see if your IDMEF messages goes from one to another topics
  and how they are handled
  * URL: `http://<node-ip>:30192`
* Query manually Elasticsearch
  * API: `http://elastic:elastic@<node-ip>:30292`

# Example with minikube

## Install minikube

Follow the procedure from your Linux distribution: [Minikube get started](https://minikube.sigs.k8s.io/docs/start/)

## Start minikube

Basically starting minikube is just running the command `minikube start` but
because we need to push some files to containers, we need to mount a local
folder. In this repository, we choose `/tmp/minikube`. Also, we want to be able
to use the full potential of your machine so put memory and cpu to `max`

At the end, the "start" command is the next one.
```
minikube start --mount --mount-string="/tmp/minikube:/mnt/minikube" --memory max --cpus max --driver podman 
```

Note: Remember to `delete` your minikube if you already have one. If you do
not, the previous parameters will not be taken in account.

## Enable minikube metrics

Metrics alow you to have CPU and Memory usage in live.

Run the following command to enable metrics
```
minikube addons enable metrics-server
```

## Start the Kubernetes dashboard

The web interface is great and usefull, we recommand to use it.

Run the following command to start it and force the port to 20123
```
minikube dashboard --port 20123
```

## Access services

First of all, you ned to know your node IP. With minikube, you can run the
command `minikube ip` but in a more general way, you can get it with the
command `kubectl get nodes -o wide`

To access the GUI:
```
http://<node-ip>:30080
```

To access the Elasticsearch API:
```
http://<node-ip>:30292
```

To access the kafdrop for Kafka debug:
```
http://<node-ip>:30192
```

To send logs to logstash:
```
http://<node-ip>:30514
```

## Add NGINX reverse proxy

To access your S4S prototype outside of your local network, you need a reverse
proxy. Here is an example of NGINX configuration if your minikube ip is
192.168.49.2:
```
server {
    listen 80;
    listen [::]:80;
    server_name _;

    location / {
        proxy_pass http://192.168.49.2:30080/;
        include proxy_params;
    }

    location /minikube/ {
        proxy_pass http://127.0.0.1:20123/;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /kafdrop/ {
        proxy_pass http://192.168.49.2:30192/;
        include proxy_params;
        sub_filter 'href="/' 'href="/test/';
        sub_filter 'src="/' 'src="/test/';
        sub_filter 'action="/' 'action="/test/';
        sub_filter_once off;
    }
}
````
