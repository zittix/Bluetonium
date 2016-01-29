//
//  Manager.swift
//  Bluetonium
//
//  Created by Dominggus Salampessy on 23/12/15.
//  Copyright © 2015 E-sites. All rights reserved.
//

import Foundation
import CoreBluetooth

public class Manager: NSObject, CBCentralManagerDelegate {
    
    public var bluetoothEnabled: Bool {
        get {
            return cbManager.state == .PoweredOn
        }
    }
    private(set) public var scanning = false
	private(set) public var connectedDevices: [String:Device] = [:]
    private(set) public var foundDevices: [Device] = []
    public weak var delegate: ManagerDelegate?
    
    private var cbManager: CBCentralManager!
	
    // MARK: Initializers
    
    public init(background: Bool = false) {
        super.init()
        
        let options: [String: String]? = background ? [CBCentralManagerOptionRestoreIdentifierKey: ManagerConstants.restoreIdentifier] : nil

        cbManager = CBCentralManager(delegate: self, queue: nil, options: options)
    }
    
    // MARK: Public functions
    
    /**
     Start scanning for devices advertising with a specific service.
     The services can also be nil this will return all found devices.
     Found devices will be returned in the foundDevices array.
    
     - parameter services: The UUID of the service the device is advertising with, can be nil.
	 - parameter options: Option passed directly to CoreBluetooth
    */
	public func startScanForDevices(advertisingWithServices services: [String]? = nil, options: [String:AnyObject]? = nil) {
        if scanning == true {
            return
        }
        scanning = true
        
        foundDevices.removeAll()
        cbManager.scanForPeripheralsWithServices(services?.CBUUIDs(), options: options)
    }
    
    /**
     Stop scanning for devices.
     Only possible when it's scanning.
     */
    public func stopScanForDevices() {
        scanning = false
        
        cbManager.stopScan()
    }
    
    /**
     Connect with a device. This device is returned from the foundDevices list.
    
     - parameter device: The device to connect with.
     */
    public func connectWithDevice(device: Device, timeout: CFTimeInterval = ManagerConstants.defaultConnectionTimeout) {
        // Only allow connecting when it's not yet connected to another device.
        if let _ = self.deviceForUUID(device.deviceUuid) {
            return
        }
        
        connectedDevices[device.deviceUuid] = device
		
        connectToDevice(device, timeout: timeout)
    }
    
    /**
     Disconnect from the connected device.
     Only possible when not connected to a device.
     */
	public func disconnectFromDevice(device: Device) {
        // Reset stored UUID.
        removeConnectedUUID(device.deviceUuid)
        
        guard let peripheral = connectedDevices[device.deviceUuid] else {
            return
        }
        
        if peripheral.peripheral.state != .Connected {
            connectedDevices.removeValueForKey(device.deviceUuid)
        } else {
            peripheral.state = .Disconnecting
            cbManager.cancelPeripheralConnection(peripheral.peripheral)
        }
    }
    
    // MARK: Private functions
	
	private func deviceForUUID(uuid: String) -> Device? {
		return connectedDevices[uuid]
	}
	
	private func connectToDevice(device: Device, timeout: CFTimeInterval) {
		
		// Store connected UUID, to enable later connection to the same peripheral.
		storeConnectedUUID(device.deviceUuid)
		
		if device.peripheral.state == .Disconnected {
			
			dispatch_async(dispatch_get_main_queue()) { () -> Void in
				// Send callback to delegate.
				self.delegate?.manager(self, willConnectToDevice: device)
			}
			
			// If not the connection will be retriggerdd when Bluetooth is back on.
			if(self.bluetoothEnabled) {
				cbManager.connectPeripheral(device.peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: NSNumber(bool: true)])
				dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(Double(timeout) * Double(NSEC_PER_SEC))), dispatch_get_main_queue()) {
					if device.state == .Connecting {
						self.cbManager.cancelPeripheralConnection(device.peripheral)
						self.centralManager(self.cbManager, didFailToConnectPeripheral: device.peripheral, error: NSError(domain: ManagerConstants.errorDomain, code: 0x1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("Connection timeout", comment: "")]))
					}
				}
			}
		}
		
    }
	
    /**
     Store the connectedUUID in the UserDefaults.
     This is to restore the connection after the app restarts or runs in the background.
     */
    private func storeConnectedUUID(UUID: String) {
		let defaults = NSUserDefaults.standardUserDefaults()
		let arr : [String]
		if var arrtmp = defaults.objectForKey(ManagerConstants.UUIDStoreKey) as? [String] {
			arrtmp.append(UUID);
			arr = arrtmp
		} else {
			arr = [UUID]
		}
		defaults.setObject(arr, forKey: ManagerConstants.UUIDStoreKey)
		defaults.synchronize()
    }
	
	private func removeConnectedUUID(UUID: String) {
		let defaults = NSUserDefaults.standardUserDefaults()

		if var arrtmp = defaults.objectForKey(ManagerConstants.UUIDStoreKey) as? [String] {
			if let idx = arrtmp.indexOf(UUID) {
				arrtmp.removeAtIndex(idx)
			}
			defaults.setObject(arrtmp, forKey: ManagerConstants.UUIDStoreKey)
			defaults.synchronize()
		}
	}
	
    /**
     Returns the stored UUID if there is one.
     */
    private func storedConnectedUUID() -> [String]? {
        let defaults = NSUserDefaults.standardUserDefaults()
		if let arr = defaults.objectForKey(ManagerConstants.UUIDStoreKey) as? [String] where arr.count > 0 {
			return arr
		}
		
		return nil
    }
    
    // MARK: CBCentralManagerDelegate
    
    @objc public func centralManager(central: CBCentralManager, willRestoreState dict: [String : AnyObject]) {
        print("willRestoreState: \(dict[CBCentralManagerRestoredStatePeripheralsKey])")
    }
    
    @objc public func centralManagerDidUpdateState(central: CBCentralManager) {
        
        if central.state == .PoweredOn {
            
            if connectedDevices.count > 0 {
				
				for device in connectedDevices.values {
					connectToDevice(device, timeout: ManagerConstants.defaultConnectionTimeout)
				}
                
            } else if let storedUUID = storedConnectedUUID() {
				for uuid in storedUUID {
					if let peripheral = central.retrievePeripheralsWithIdentifiers([NSUUID(UUIDString: uuid)!]).first {
						dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(0.2 * Double(NSEC_PER_SEC))), dispatch_get_main_queue()) {
							let device = Device(peripheral: peripheral)
							device.registerServiceManager()
							self.connectWithDevice(device)
						}
					}
				}
            }
			
        } else if central.state == .PoweredOff {
            
            dispatch_async(dispatch_get_main_queue()) { () -> Void in
				for c in self.connectedDevices.values {
					c.serviceModelManager.resetServices()
					self.delegate?.manager(self, disconnectedFromDevice: c, retry: true)
				}
            }
            
        }
    }
    
    @objc public func centralManager(central: CBCentralManager, didDiscoverPeripheral peripheral: CBPeripheral, advertisementData: [String : AnyObject], RSSI: NSNumber) {
        let device = Device(peripheral: peripheral);
        if !foundDevices.contains(device) {
            foundDevices.append(device)
            
            // Only after adding it to the list to prevent issues reregistering the delegate.
            device.registerServiceManager()
            
            dispatch_async(dispatch_get_main_queue()) { () -> Void in
                self.delegate?.manager(self, didFindDevice: device)
            }
        }
    }
	
    @objc public func centralManager(central: CBCentralManager, didConnectPeripheral peripheral: CBPeripheral) {
        if let c = connectedDevices[peripheral.identifier.UUIDString] {
            dispatch_async(dispatch_get_main_queue()) { () -> Void in
                // Send callback to delegate.
                self.delegate?.manager(self, connectedToDevice: c)
                
                // Start discovering services process after connecting to peripheral.
                c.serviceModelManager.discoverRegisteredServices()
            }
        }
    }
    
    @objc public func centralManager(central: CBCentralManager, didFailToConnectPeripheral peripheral: CBPeripheral, error: NSError?) {
		
        print("didFailToConnect \(peripheral)")
		
		if let c = connectedDevices[peripheral.identifier.UUIDString] {
			connectedDevices.removeValueForKey(c.deviceUuid)
			removeConnectedUUID(c.deviceUuid)
			self.delegate?.manager(self, failedToConnectToDevice: c)
		}
		
    }
    
    @objc public func centralManager(central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: NSError?) {
		if let device = connectedDevices[peripheral.identifier.UUIDString] {
            device.serviceModelManager.resetServices()
			
			let willRetry : Bool
			
            if device.state == .Disconnecting {
                // Disconnect initated by user.
				connectedDevices.removeValueForKey(device.deviceUuid)
                device.state = .Disconnected
				willRetry = false
            } else {
                // Send reconnect command after peripheral disconnected.
                // It will connect again when it became available.
                central.connectPeripheral(peripheral, options: nil)
				willRetry = true
            }
            
            dispatch_async(dispatch_get_main_queue()) { () -> Void in
                self.delegate?.manager(self, disconnectedFromDevice: device, retry: willRetry)
            }
        }
    }
    
}


public protocol ManagerDelegate: class {
    
    /**
     Called when the `Manager` did find a peripheral and did add it to the foundDevices array.
     */
    func manager(manager: Manager, didFindDevice device: Device)
    
    /**
     Called when the `Manager` is trying to connect to device
     */
    func manager(manager: Manager, willConnectToDevice device: Device)
    
    /**
     Called when the `Manager` did connect to the device.
     */
    func manager(manager: Manager, connectedToDevice device: Device)
	
	/**
	Called when the `Manager` failed to connect to the device.
	*/
	func manager(manager: Manager, failedToConnectToDevice device: Device)
	
    /**
     Called when the `Manager` did disconnect from the device.
     Retry will indicate if the Manager will retry to connect when it becomes available.
     */
    func manager(manager: Manager, disconnectedFromDevice device: Device, retry: Bool)
    
}


private struct ManagerConstants {
    static let errorDomain = "nl.e-sites.bluetooth-kit.error"
    static let restoreIdentifier = "nl.e-sites.bluetooth-kit.restoreIdentifier"
    static let UUIDStoreKey = "nl.e-sites.bluetooth-kit.UUID"
	static let defaultConnectionTimeout = 10.0
}


internal extension CollectionType where Generator.Element == String {
    
    func CBUUIDs() -> [CBUUID] {
        return self.map({ (UUID) -> CBUUID in
            return CBUUID(string: UUID)
        })
    }
    
}
