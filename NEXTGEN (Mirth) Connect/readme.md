# Monitoring NEXTGEN Connect (Mirth Connect) using PRTG

With this powershell script you are able to monitor your [NEXTGEN Connect](https://www.nextgen.com/products-and-services/integration-engine) installation. 

Since version 4.3 Mirth has a REST API which is queried by the script. This allows two types of sensors to be created in PRTG. The Mirth System Health Sensor provides system values such as CPU load, free memory, and free hard disk space. To monitor individual interfaces, the Channel Sensor monitors the number of messages sent and received as well as faulty and buffered messages per channel. With these sensors, it is now possible to monitor important parameters of the communication server and thus to integrate a central and important part of the medical infrastructure in PRTG. The sensors can also be created with a template, which simplifies the integration. By regularly performing Auto-Discovery, Mirth's newly created channels can be integrated directly into PRTG.

### Installation
- Deploy prtg_mirth.ps1 to <prtg_folder>\custom sensors\EXEXML
- Deploy prtg_mirth_template.odt to <prtg_folder>\templates

Following metrics can be monitored:
 
#### Mirth System Health:
- CPU %
- Free Memory
- Free Disk Space

```
prtg_mirth.ps1 <IP/DNS> <port> <username> <password> "system" 
```

![Image of Mirth System Health Sensor](./img/mirth_system_health.png)

#### Channel <Channel Name>:
- Received
- Sent 
- Filtered
- Error
- Queued

```
prtg_mirth.ps1 <IP/DNS> <port> <username> <password> "channel" <channelID> 
```
![Image of Mirth Channel Sensor](./img/mirth_channel.png)

# Auto-Discovery support via Template
  - Select "NEXTGEN (Mirth) Connect" template in Device Settings as template
  - Set Username and Password in the Device Linux credentials
  - Run Auto-Discovery with specified template
  - Newly added channels from Mirth will be added in PRTG if you schedule a reoccuring Auto-Discovery for this Device

# Debugging
- Add -Verbose parameter to enable logging to console
