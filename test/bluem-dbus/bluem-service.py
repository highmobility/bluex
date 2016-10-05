#!/usr/bin/env python3

from gi.repository import GObject
import dbus
import dbus.service
import dbus.glib
import syslog
import random

syslog.openlog("BlueMock-DBus")

session_bus = dbus.SessionBus()
service = dbus.service.BusName("org.bluem", bus=session_bus)

def _log(text):
    syslog.syslog(syslog.LOG_ALERT, text)


def randomMAC():
    return [ 0x00, 0x16, 0x3e,
            random.randint(0x00, 0x7f),
            random.randint(0x00, 0xff),
            random.randint(0x00, 0xff) ]

def mac_to_address(mac):
    return ':'.join(map(lambda x: "%02x" % x, mac))


def dbus_dev_address(mac):
    return '_'.join(map(lambda x: "%02x" % x, mac))

class MockController(dbus.service.Object):
    def __init__(self, bus_name, object_path="/org/mock"):
        dbus.service.Object.__init__(self, bus_name, object_path)

    @dbus.service.method("org.mock")
    def AddDevice(self):
        device_mac =randomMAC()
        device_path = "/org/bluem/hci1/dev_%s" % dbus_dev_address(device_mac)
        details = {
                "org.bluem.Device1": {
                    "Adapter": "/org/bluem/hci1",
                    "Address": mac_to_address(device_mac),
                    "Alias": "bluemock-0",
                    "Connected": "false",
                    "Name": "bluemock-0",
                    "RSSI": "-71",
                    "UUIDs": ""
                }
        }
        blue_mock.InterfacesAdded(device_path, details)
        _log("Adding random device %s to path " %(device_mac))
        BlueMockDevice(service, object_path=device_path)
        return device_path

class BlueMock(dbus.service.Object):
    """
    <node>
        <interface name="org.freedesktop.DBus.ObjectManager">
            <signal name="InterfacesAdded">
                <arg name="object" type="o"/>
                <arg name="interfaces" type="a{sa{sv}}"/>
            <signal>
        </interface>
    </node>
    """

    def __init__(self, bus_name, object_path="/"):
        dbus.service.Object.__init__(self, bus_name, object_path)

    @dbus.service.signal("org.freedesktop.DBus.ObjectManager")
    def InterfacesAdded(self, obj, interfaces):
        _log("InterfacesAdded .. %s, %s" % (obj, interfaces))



class BlueMockDevice(dbus.service.Object):
    def __init__(self, bus_name, object_path):
        dbus.service.Object.__init__(self, bus_name, object_path)
        self.connected = False

    @dbus.service.method("org.bluem.Device1")
    def Connect(self):
        _log("Connecting ...")
        self.connected = True

    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature='s', out_signature='a{sv}')
    def GetAll(self, interface):
        return {"Connected": self.connected}

class BlueMockHCI(dbus.service.Object):
    def __init__(self, bus_name, object_path="/"):
        dbus.service.Object.__init__(self, bus_name, object_path)


    @dbus.service.method("org.bluem.Adapter1")
    def StartDiscovery(self):
        _log("StartDiscovery ...")
        pass



blue_mock = BlueMock(service, object_path="/")
BlueMockHCI(service, object_path="/org/bluem/hci1")
MockController(service)

manager = dbus.Interface(session_bus.get_object("org.bluem", "/"), "org.freedesktop.DBus.ObjectManager")

mainloop = GObject.MainLoop()
mainloop.run()
