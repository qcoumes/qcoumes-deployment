
Zigbee
======

*Uses [`composes/zigbee.yaml`](../composes/zigbee.yaml)*

This template allow you to setup a Zigbee sensors to Grafana stack.

*This guide assume `traefik` is running, see the main [README.md](../README.md).*                            

## Services

* `zigbee2mqtt` - Zigbee to MQTT bridge. Also allow to change the parameters of your sensors.                        
* `mosquitto` - MQTT Broker.
* `telegraf` - Ingest MQTT and save it to InfluxDB.
* `influxdb` - Store your sensors values in time-series.
* `grafana` - Allow to create visualization for your data.


## Template structure

```
templates/zigbee/
├── docker-compose.yml
├── grafana
├── influxdb
│   ├── config
│   └── data
├── mosquitto
│   ├── config
│   │   └── mosquitto.conf
│   ├── data
│   └── log
├── telegraf
│   └── telegraf.conf
└── zigbee2mqtt
```


## Setup

1. Copy the template in the `live` directory.
	* `cp -r templates/zigbee/ live/zigbee`

2. Setup your Zigbee receiver in `composes/zigbee.yaml`'s `zigbee2mqtt` service. 
	You need to find the path used by your Zigbee receiver. Plug it in and run `ls -l /dev/serial/by-id/`, you should see something like :

	* `usb-ITead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_f830ff28389eef118099d2a661ce3355-if00-port0 -> ../../ttyUSB0`.

	Use this path in `composes/zigbee.yaml`'s `zigbee2mqtt` service:

	```
	    devices:
	      - /dev/serial/by-id/usb-ITead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_f830ff28389eef118099d2a661ce3355-if00-port0:/dev/zigbee
	```
3. Setup the Traefik rules for `zigbee2mqtt`, `influxdb` and `grafana` by editing the corresponding variables in `live/zigbee/.docker.env`.
	For instance :
	```
	export ZIGBEE2MQTT_TRAEFIK_RULE='Host(`zigbee2mqtt.zigbee.domain.com`)'
	export INFLUXDB_TRAEFIK_RULE='Host(`influxdb.zigbee.domain.com`)'
	export GRAFANA_TRAEFIK_RULE='Host(`grafana.zigbee.domain.com`)'
   ```

4. Create a password for `zigbee2mqtt`.
	Run `htpasswd -nb admin '<your-password>'` and copy the ouput in the `ZIGBEE2MQTT_PASSWORD` variable of `live/zigbee/.docker.env`.


5. Setup InfluxDB.
	Run `./bin/up.sh zigbee`, go to your InfluxDB domain address, and create:
	* an organization
    * an admin user
    * buckets for your sensors, for example `weather` and `power`
    * a write token for Telegraf
    * a read token for Grafana
	
6. Add the write token to Telegraf.
	Open `live/zigbee/telegraf/telegraf.conf` and replace the occurrences of `<TOKEN>` with the write token created in the step before. You then need to recreate the services: `./bin/recreate.sh zigbee`.

7. Connect Grafana to InfluxDB.
	Go to your Grafana domain adress and login using the default credentials: `admin`  / `admin` and immediately change the password.
	Go to Connections → Data sources → Add data source → InfluxDB and add a new source:
	```
	Query language: Flux
	URL: http://<infludb-host>
	Organization: <InfluxDB organization>
	Token: <Grafana read token>
	Default bucket: `weather` or `power`
	```

## Adding a Zigbee device

To add a new device, go to your Zigbee2MQTT domain address, authenticate using the credentials defined at setup step **4.** and click on the "allow pairing button". Follow your Zigbee sensor's manual to see how to allow pairing on its side.

Once paired, the device will appear in the Zigbee2MQTT UI. It is necessary to rename it so that Telegraff picks up the data and sends it to the corresponding InfluxDB bucket.

By default, the sensors prefixed with `aqara_*` go to the `weather` bucket, and those prefixed with `plug_*` go the to `power` bucket. This behavior can be changed by modifying the `live/zigbee/telegraf/telegraf.conf` file and restarting the service.

