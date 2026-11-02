Zigbee
======

*Uses [`composes/zigbee.yml`](../../composes/zigbee.yml)*

This template allow you to setup a Zigbee sensors to Grafana stack, with Home Assistant and a local voice assistant
(speech-to-text and text-to-speech).

*This guide assume `traefik` is running, see the main [README.md](../../README.md).*

## Services

* `zigbee2mqtt` - Zigbee to MQTT bridge. Also allow to change the parameters of your sensors.
* `mosquitto` - MQTT Broker.
* `telegraf` - Ingest MQTT and save it to InfluxDB.
* `influxdb` - Store your sensors values in time-series.
* `grafana` - Allow to create visualization for your data.
* `homeassistant` - Home automation, reads the devices through MQTT.
* `wyoming-whisper` - Speech-to-text for Home Assistant's voice assistant ([Wyoming](https://github.com/rhasspy/wyoming)
  protocol, `tiny-int8` model, french).
* `wyoming-piper` - Text-to-speech for Home Assistant's voice assistant (Wyoming protocol, voice `en_US-glados-medium`).

The model and voice are set in the `command` of the corresponding services. They are downloaded on first start into
`wyoming-whisper/` and `wyoming-piper/`.

An `ollama` service (local LLM for the voice assistant) is present but commented out in the compose file.


## Template structure

```
templates/zigbee/
├── .docker.env                 # Traefik rules and Zigbee2MQTT password
├── grafana/
├── homeassistant/              # Home Assistant /config, created on first start
├── influxdb/
│   ├── config/
│   └── data/
├── mosquitto/
│   ├── config/
│   │   └── mosquitto.conf
│   ├── data/
│   └── log/
├── telegraf/
│   └── telegraf.conf
├── wyoming-piper/              # Downloaded voices
├── wyoming-whisper/            # Downloaded models
└── zigbee2mqtt/
```


## Setup

1. Copy the template in the `live` directory.
	* `cp -r templates/zigbee/ live/zigbee`

2. Setup your Zigbee receiver in `composes/zigbee.yml`'s `zigbee2mqtt` service.
	You need to find the path used by your Zigbee receiver. Plug it in and run `ls -l /dev/serial/by-id/`, you should see something like :

	* `usb-ITead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_f830ff28389eef118099d2a661ce3355-if00-port0 -> ../../ttyUSB0`.

	Use this path in `composes/zigbee.yml`'s `zigbee2mqtt` service:

	```
	    devices:
	      - /dev/serial/by-id/usb-ITead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_f830ff28389eef118099d2a661ce3355-if00-port0:/dev/zigbee
	```
3. Setup the Traefik rules for `zigbee2mqtt`, `influxdb`, `grafana` and `homeassistant` by editing the corresponding
   variables in `live/zigbee/.docker.env`. For instance :
	```
	export ZIGBEE2MQTT_TRAEFIK_RULE='Host(`zigbee2mqtt.zigbee.domain.com`)'
	export INFLUXDB_TRAEFIK_RULE='Host(`influxdb.zigbee.domain.com`)'
	export GRAFANA_TRAEFIK_RULE='Host(`grafana.zigbee.domain.com`)'
	export HOMEASSISTANT_TRAEFIK_RULE='Host(`homeassistant.zigbee.domain.com`)'
	```
	Each host needs its own DNS record.

4. Create a password for `zigbee2mqtt`.
	Run `htpasswd -nbB admin '<your-password>'` and copy the output in the `ZIGBEE2MQTT_PASSWORD` variable of
	`live/zigbee/.docker.env`, between single quotes (the hash contains `$`).


5. Setup InfluxDB.
	Run `./bin/up.sh zigbee`, go to your InfluxDB domain address, and create:
	* an organization
	* an admin user
	* buckets for your sensors, for example `weather` and `power`
	* a write token for Telegraf
	* a read token for Grafana

6. Add the write token to Telegraf.
	Open `live/zigbee/telegraf/telegraf.conf` and replace the occurrences of `<TOKEN>` with the write token created in
	the step before. You then need to recreate the services: `./bin/recreate.sh zigbee`.

7. Connect Grafana to InfluxDB.
	Go to your Grafana domain address and login using the default credentials: `admin`  / `admin` and immediately change the password.
	Go to Connections → Data sources → Add data source → InfluxDB and add a new source:
	```
	Query language: Flux
	URL: http://<infludb-host>
	Organization: <InfluxDB organization>
	Token: <Grafana read token>
	Default bucket: `weather` or `power`
	```

8. Setup Home Assistant.
	On first start, Home Assistant creates its configuration in `live/zigbee/homeassistant/`. It refuses requests
	coming through a reverse proxy until told to trust it: add the following to
	`live/zigbee/homeassistant/configuration.yaml`, with the subnet of the `web` network
	(`docker network inspect web --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}'`), then
	`docker restart zigbee-homeassistant`:
	```yaml
	http:
	  use_x_forwarded_for: true
	  trusted_proxies:
	    - 172.19.0.0/16
	```
	Prefer the subnet to Traefik's own IP: the IP can change when Traefik is recreated.

	Go to your Home Assistant domain address to create the admin account, then add the integrations:
	* **MQTT**: broker `mosquitto`, port `1883`, no credentials (Mosquitto allows anonymous clients: it is only
	  reachable on the internal `zigbee` network).
	* **Wyoming Protocol**: host `wyoming-whisper`, port `10300` (speech-to-text), then host `wyoming-piper`, port
	  `10200` (text-to-speech). Select them in Settings → Voice assistants.

## Adding a Zigbee device

To add a new device, go to your Zigbee2MQTT domain address, authenticate using the credentials defined at setup step
**4.** and click on the "allow pairing button". Follow your Zigbee sensor's manual to see how to allow pairing on its
side.

Once paired, the device will appear in the Zigbee2MQTT UI. It is necessary to rename it so that Telegraf picks up the
data and sends it to the corresponding InfluxDB bucket.

By default, the sensors prefixed with `aqara_*` go to the `weather` bucket, and those prefixed with `plug_*` go the to
`power` bucket. This behavior can be changed by modifying the `live/zigbee/telegraf/telegraf.conf` file and restarting
the service.
