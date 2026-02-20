# Root Cause Analysis

Several [Mobvoi Tichome Mini](https://ausdroid.net/2017/11/19/mobvoi-tichome-mini-australian-review-google-assistant-speakers/) (google cast capable) smart speakers,  were purchased off the shelf from an Australian electronics retail store in late November 2022, and they were still [on sale](https://www.jaycar.com.au/tichome-mini-smart-speaker-white-with-google-assistant/p/XC6001) in December 2022, although it appears no longer available from sometime in 2023.

The device appears to have been released in 2017. Out of the box the firmware appears to date from October 2017 (version 012). When first paired with the Google Assistant app the device will self-update its firmware to a version from 2019 (version 027).

The vulnerability is present both in the unboxed, unpaired device and a self-updated device.

The device has a mediatek SOC arm7hf 4-core processor with only two cores enabled for Linux, and 512MB of RAM, and includes Wifi capable of concurrent AP and client mode, and Bluetooth. There is a supporting STM ARM microcontroller, a power management function IC, i2c LED controller and a DAC. The firmware is an Android derived embedded Linux, with read only /system and /chrome partitions and a read/write /data configuration partition residing in 512MB flash. The binaries include a Google chrome cast client.
After the device has paired there are multiple processes that run, including what an interprocess communication daemon, `eipcd`, this is separate to the standard Android IPC. The program `eipcd` receives packets on several UDP ports and receives and transmits with multiple other processes. There is no iptables firewall. Several `eipcd` receiving UDP ports are open on `0.0.0.0`.
The process `eipcd` receives packets on UDP port 35670 and then depending on the content rebroadcasts these to other processes and/or handles them locally. 
One locally handled command appears to be intended to request copying files off the device using the tftp. However, the intended operation fails because the tftp client binary is not present on the device.
The TFTP copy request uses two parameters extracted from the UDP packet: the full path to a file on the embedded filesystem, and a destination hostname.
This tftp operation is attempted, and is vulnerable because the code makes two `system()` calls, first `cp` to copy the requested file to a known location on the flash, and then `tftp` to execute the (missing) tftp client to the requested host.

Both of these calls use `system()` without any sanitisation, thus it is possible to inject `"$(arbitrary-command)"` in place of the requested filename in the UDP packet and have that execute on the device when the `cp` operation is run. Due to the way the data is parsed it does not appear to be feasible to construct the packet in a way to have both `system()` calls execute unique commands - instead they end up executing the same command twice if attempted.

There is a second vulnerability in the same function, a NULL pointer dereference that will crash `eipcd` in the same function immediately before the `system()` call.

There is a third vulnerability, a `system()` call without any sanitisation leading to injection in a different function that processes a different identified UDP packet. Because I have only limited experience in submitting a CVE I'm not sure if that should be a separate report so I have detailed it together below.

## Code flow from input to the vulnerable condition

The firmware was dumped after gaining access to the device by soldering a serial port, and later, updated via remote automated update, although this is now returning a 404 in 2025. The analysis was performed by decompiling the `eipcd` program, which appears to be written in C and/or C++

The process `eipcd` spawns a pthread that receives UDP packets from port 35670 and then enters a switch statement and/or series of `if()` statements. There is additional processing that may involve writing the message to a queue for rebroadcasting to other listening processes but that is not relevant to this bug.

The message switching happens ultimately in function `ipcd_analysis_core()`

The UDP packet has the following format:

-  4 Bytes  ==> message identifier type, in the vulnerable cases, 0x13 or 0x12

-  4 Bytes  ==> this is an internal identifier intended to direct the packet via the IPC interface, but in this case is never processed
    
-  4 Bytes  ==> this is a size field that seems to be used when copying the packets for rebroadcast, it may not be processed in this case but for safety I set it to the size of the UDP payload

-  128 bytes  ==> this is a path on the filesystem. It need not be zero terminated as `strncpy` is used to extract the path.

-  remaining bytes ==> hostname for TFPT interpreted as zero terminated

There are two relevant messages.

- Message 0x13 appears to be intended to execute a TFTP client operation to transfer an arbitrary requested file off the device

- Message 0x12 appears to be intended to execute a TFTP client operation to transfer a log file off the device

When `ipcd_analysis_core()` identifies 0x13, a function called `ipc_misc_tftp_upload()` is called with two arguments, a pointer to the start of the 128 byte buffer, and a pointer to the start of the hostname

When `ipcd_analysis_core()` identifies 0x12, a function called `ipc_misc_tftp_upload_log()` is called with two arguments, a pointer to an internal variable I named log_path, and a pointer to the start of the hostname

# Buffer Size, Injection Point, etc.

## Primary and Second Vulnerability

Function `ipc_misc_tftp_upload()` has the following pseudocode:

```
char stackLocal[512]
basename = strrchr(ptrToBuffer128, '/')
vsnprintf(stackLocal, 512, "cp %s %s", ptrToBuffer128, basename)
system(stackLocal1)
vsnprintf(stackLocal, 512, "tftp -p -r %s %s", basename, hostname)
```

The primary vulnerability is because on this environment, we can arrange for a string such as (double quotes inclusive) `"$(linux command &)"` to be in `ptrToBuffer128`, and this will cause a subshell to fork and run a `linux command` in the background. It may be possible to omit the `&` however I consistently ran the exploit with it.

Care must be taken when setting the value of `ptrToBuffer128`. If there is no trailing backslash and the command has no other backslashes then the command will be executed a total of three times in this function, potentially with unexpected side effects. If there is no trailing slash, then an unexpected command may be run twice in addition to the exploit command.

Thus, the UDP payload is successful when `ptrToBuffer128` is formed with backslashes at each end, e.g as (double quotes inclusive) `/"$(unix/command args > redirection,etc &)"/` this leaves a total of up to 120 characters for the actual command (after subtracting 2 backslashes, 2 quotes, $, 2 brackets and `&`).

The operation may fail if not padded out to 128 bytes total as `ipcd_analysis_core` may overrun the expected buffer when looking for the hostname

By the same reasoning, it should be possible to inject a command into hostname however I have not tested this.

The Second Vulnerability occurs if there are no backslashes; `strrchr()` will return NULL eventually if there is a 0 terminator in `prtToBuffer128` or if there is no backslash in the hostname component; the result will be a segfault when `vsnprintf()` is called, crashing `eipcd`. This may cause a denial of service some unknown time later as it appears that `eipcd` may send messages between other processes when doing operations such as a firmware update check or device reset, and possibly other operations.

## Third Vulnerability

This is very similar in scope to the Primary vulnerability except in the function `ipc_misc_tftp_upload_log()`

In this case, the filename is internally generated, so only the hostname is available for exploitation.

# Suggested fixes

- escape arguments to `system()` when they are derived from external input, i.e. OWASP #1 (injection) and #8 (insecure deserialisation), CWE-78 Improper Neutralization of Special Elements used in an OS Command

- test the return value of `strrchr()` for NULL, CWE-252 Unchecked Return Value

- at a the engineering level, this functionality is probably not intended for production use and should be removed, especially as it cannot work as there is no tftp binary. Possibly the eipcd component is a third party component, CWE-1164 Irrelevant code

- bind the IPC UDP port to only receive on 127.0.0.1 (although the other faults might still be exploitable if another beachhead on the device was made) - CWE-1327 Binding to an Unrestricted IP Address

# Proof-of-Concept

All the proof of concepts use bash, echo -e, and socat to inject the UDP packet to achieve the desired outcome.

These all seem to work better from Linux rather than in WSL for reasons I haven't spent time troubleshooting, possibly firewall or A/V related.

The first test, `inject-ping-command-poc.sh <speaker_ip> <wireshark_ip>` causes the device to send a ping back to the caller, and can be observed using Wireshark.
Run this first. 

The second test `inject-reverse-shell-command.sh <speaker_ip> <netcat_ip> <netcat_port>` executes a reverse shell to the host. Note, this requires two packets, because for some reason when too many file descriptor redirections are present even within quotes the local shell system() call seems to error. The first packet writes a script to `/data` which is then executed by the second packet. The script uses a while loop to retain persistence. Ensure the port can come through the firewall!

Both tests take the speaker IP address as first argument.

The first test takes an IP address to ping as second argument.

The second test takes an IP address and then port to contact a reverse shell as netcat as second and third argument.

The scripts do not sanity check the IP addresses...

The third test is similar to the first, except is uses the 0x12 message and the hostname variable instead.
Use, `inject-ping-command-poc-cmd12-instead.sh <speaker_ip> <wireshark_ip>` to cause  the device to send a ping back to the caller, and can be observed using Wireshark.

The final test will segfault eipcd, run `inject-crash-command-poc.sh <speaker-ip>`

After this you will need to reboot the device unless you had a shell; note, eipcd can't be restarted until all child tree processes have been killed.

The attachment is a tar file with several shell scripts that print help when needed.

Note if conditions are not optimal, it may be quickest to power cycle the device if eipcd crashed or the shell got out of sync due to a firewall on the attackers machine being on then off, etc.

# Software Download

As a part of the analysis the firmware update process was inspected and a download made of the latest firmware, this came from the following:

```
curl -i -v 'http://mushroom.chumenwenwen.com/api/latest.json?app=TichomeMini&channel=release&curversion=18853&uid=740447123456
```

This link no longer works.

The uid fails if all 0's, the last 6 digits are redacted from my device/

The result is JSON:
```
{
    "app": "TichomeMini",
    "channel": "release",
    "changelog": "google cast1.40",
    "created_at": "2019-10-21",
    "description": "",
    "counter": 29580,
    "version": "027",
    "enabled": true,
    "url": "https://d1ryccdlg2s6do.cloudfront.net/support_ticwear_com/ota/mushroom/full/TichomeMini-release-027-1571648040119.zip",
    "diff_from": "",
    "valid": true,
    "number": 27,
    "size": 126033388,
    "compatibility": "",
    "force_update": false,
    "md5": "4965783ec57788f80841ea97d49ffce7",
    "upload_status": ""
}
```

The direct download link at the time: https://d1ryccdlg2s6do.cloudfront.net/support_ticwear_com/ota/mushroom/full/TichomeMini-release-027-1571648040119.zip 

The Linux programs `binwalk`, `cpio` and the python program `ubi-reader` can be used to extract the firmware initramfs and chrome and system partitions. The program eipcd exists in the system partition. It can be analysed with Ghidra, one tactic would be to first find the tftp command string and work back to the system() function call and backward from there.

The FCC filing for the device is https://fccid.io/2AHEA-TICHOMEMINI

# Detection Guidance

The UDP ports are not encrypted. One would assume then that an IPS/IDS rule could be created to search for `0x13000000(4bytes)(4bytes)(zero terminated ascii string starting with /"$( and finishing with &)"/` and various combinations of whitespace and at least 144 bytes long. And of course on UDP port 35670.

Better though, scan for unauthorised Chromecast devices and audit authorised devices... these should probably not be on the same network as high value intellectual property.

It was simple to use a Raspberry Pi or an openwrt toolkit to cross compile arm code and upload arbitrary binaries such as nmap and tcpdump onto the device after I had the shell.
