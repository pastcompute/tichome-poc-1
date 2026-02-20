# Wifi

When the device is new or factory reset, it creates an open AP `Office speaker.n017`. This is intended to be connected to be used during normal pairing. It runs a DHCP server using dnsmasq and has an IP address (and becomes local gateway) of `192.168.255.249` and you will likely get assigned `192.168.255.254`.

After pairing and until factory reset, the device will act as a client and the credentials of the home AP are saved in a file `/data/wifi/wpa_supplicant.conf`. The device does not use the wpa_supplicant credential hashing mechanism and stores the WPA passphrase in the clear.

# Cast ports

Before I disabled them, the standard cast ports of 8008, etc. were in use.

# HTTP API on port 8080

The following was able to be enumerated after reversing the onboard software. It is unclear why this is exposed externally on the device. The functions could have a test and development role.

| URL | Type | Example response | Notes|
| --- | --- | --- | -- |
| `/` | GET | <pre>{<br/>        "ManufacturerOUI":      "",<br/>        "SoftwareVersion":      "18853012",<br/>        "DeviceIPAddress":      "192.168.50.91"<br/>}</pre>| static - later firmware will return 58389027 (version 027), IP will be "Error" before binding
| `/api/system/deviceinfo` | GET | Same as `/`|
| `/api/led-light-query` | GET | <pre>{<br/>        "command":      "led-light-state",<br/>        "state":        0<br/>}</pre> |
| `/api/query-auto-poweroff` | GET | <pre>{<br/>        "command":      "auto-poweroff-info-set",<br/>        "state":        0,<br/>        "value":        0<br/>}</pre> |
| `/api/request-version` | GET | <pre>{<br/>        "command":      "info-version",<br/>        "map":  [{<br/>                        "value":        "MT8516",<br/>                        "version":      "001"<br/>                }]<br/>}</pre> |static
| `/api/system/time` | GET | <pre>{<br/>        "Curr_TimeZone":        "+8:00",<br/>        "Curr_Time":    "2022-11-24_21:16:45",<br/>        "Curr_Dst":     1,<br/>        "PowerOn_SysTime":      "2022-11-20   9:45:59",<br/>        "Current_SysTime":      "2022-11-24  10:46:45"<br/>}</pre> |
| `/api/vol-setting` | POST | <pre>{<br/>        "value":      "vol-setting",<br/>        "command":    "ack",<br/>        "code": 200<br/>}</pre> | `'{"value":2}'`<br/>Not sure what max is, tried 2 and 12
| `/api/spk-auto-poweroff` | POST | <pre>{<br/>        "value":      "spk-auto-poweroff",<br/>        "command":    "ack",<br/>        "code": 200<br/>}</pre> | `'{"state":2}'`<br/>Not sure what max is, tried 2 and 3. Maybe this is a time?
| `/api/set-led-light` | POST | <pre>{<br/>        "value":      "set-led-light",<br/>        "command":    "ack",<br/>        "code": 200<br/>}</pre> | `'{"state":5}'`<br/>Unknown what values are valid
| `api/pb-start-url`|POST| <pre>{<br/>        "value":      "pb-start-url",<br/>        "command":    "ack",<br/>        "code": 200<br/>}</pre> | `'{"value":"whatever"}'`<br/>Value is printed to stdout and ignored... calls `factory ATE_ENTER_FACTORY` (as disassembled)
| `api/upgrade-start`| ? | ? | not tested<br/>`{"command":"upgrade-start", "url":"xxx"}`<br/>Sends IPC message but nothing else listens to it :-( |
| `api/upgrade-stop`| ? | ? | not tested |
| `api/upgrade-percent`| GET |  <pre>{<br/>        "command":      "upgrade-percent",<br/>        "type": 0,<br/>        "value":        0<br/>}</pre> | |
| `api/phy-key`| POST | ? | could not get a data that worked<br/>diassembly: try `{"command":"phy-key", "value":"xxx"}`<br/>Sends `HTTP_AUTO_TEST_PHY_KEY`,`xxx` to IPC<br/>Ultimately a No-Op in appmainprog |

There is also a [directory traversal](./directory_traversal.md), from which the wpa_supplicant file can be retrieved.



