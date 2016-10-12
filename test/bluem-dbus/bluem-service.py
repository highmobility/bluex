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
        self.uuids = ['5842aec9-3aee-a150-5a8c-159d686d6363']
        self.device_path = object_path

    @dbus.service.method("org.bluem.Device1")
    def Connect(self):
        _log("Connecting ...")
        self.connected = True
        self.uuids = ['00001800-0000-1000-8000-0805f9b34fb', '713d0100-503e-4c75-ba94-3148f18d941e']

        tmp_path = "%s/service000a" % self.device_path
        BlueMockService(service, object_path=tmp_path, uuid='00001800-0000-1000-8000-0805f9b34fb')

        tmp_path = "%s/service000b" % self.device_path
        BlueMockService(service, object_path=tmp_path, uuid='713d0100-503e-4c75-ba94-3148f18d941e')
        self.PropertiesChanged("org.bluem.Device1", {"Connected": True}, [])

    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature='s', out_signature='a{sv}')
    def GetAll(self, interface):
        prop = {"Connected": self.connected, "UUIDs": self.uuids}
        _log("return all properties[%s] for %s" % (prop, interface))
        return prop

    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature='ss', out_signature='v')
    def Get(self, interface, name):
        if interface == "org.bluem.Device1" and name == "UUIDs":
            return self.uuids
        else:
            _log("don't know what is property %s for interface %s" % (name, interface))
            return {}

    @dbus.service.signal("org.freedesktop.DBus.Properties", signature='sa{sv}as')
    def PropertiesChanged(self, interface, args, l= []):
        _log("PropertiesChanged .. %s %s" % (interface, args))

class BlueMockService(dbus.service.Object):
    def __init__(self, bus_name, object_path, uuid):
        dbus.service.Object.__init__(self, bus_name, object_path)
        self.uuid = uuid
        tmp_path = "%s/char000b" % object_path
        BlueMockCharacteristic(service, object_path=tmp_path, uuid='713d0103-503e-4c75-ba94-3148f18d941e')

    @dbus.service.method("org.bluem.GattService1")
    def foo(self):
        return "foo"

    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature='ss', out_signature='v')
    def Get(self, interface, name):
        if interface == "org.bluem.GattService1" and name == "UUID":
            return self.uuid
        else:
            _log("don't know what is property %s for interface %s" % (name, interface))
            raise dbus.exceptions.DBusException(
                    "org.freedesktop.UnknownInterface",
                    "Interface %s is unknown" % interface)

class BlueMockCharacteristic(dbus.service.Object):
    def __init__(self, bus_name, object_path, uuid):
        dbus.service.Object.__init__(self, bus_name, object_path)
        self.uuid = uuid
        self.object_path = object_path
        self.value = '0000'

    @dbus.service.method("org.bluem.GattCharacteristic1")
    def StartNotify(self):
        _log("notification started for %s" % self.uuid)
        self.PropertiesChanged("org.bluem.GattCharacteristic1", {"Notifying": True}, [])

    @dbus.service.method("org.bluem.GattCharacteristic1", in_signature='sa{sv}')
    def WriteValue(self, value, options):
        _log("Write value [%s] for %s" % (value, self.uuid))
        self.PropertiesChanged("org.bluem.GattCharacteristic1", {"Value": value}, [])
        self.value = value

    @dbus.service.method("org.bluem.GattCharacteristic1", in_signature='a{sv}', out_signature='s')
    def ReadValue(self, options):
        _log("Read value [%s] for %s" % (self.value, self.uuid))
        return self.value

    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature='ss', out_signature='v')
    def Get(self, interface, name):
        if interface == "org.bluem.GattCharacteristic1" and name == "UUID":
            return self.uuid
        else:
            _log("don't know what is property %s for interface %s" % (name, interface))
            raise dbus.exceptions.DBusException(
                    "org.freedesktop.UnknownInterface",
                    "Interface %s is unknown" % interface)

    @dbus.service.signal("org.freedesktop.DBus.Properties", signature='sa{sv}as')
    def PropertiesChanged(self, interface, args, l= []):
        _log("PropertiesChanged .. %s %s" % (interface, args))




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
