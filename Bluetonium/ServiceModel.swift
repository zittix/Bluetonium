//
//  ServiceModel.swift
//  Bluetonium
//
//  Created by Dominggus Salampessy on 23/12/15.
//  Copyright © 2015 E-sites. All rights reserved.
//

import Foundation
/**
    Equatable support.
 */
public func ==(lhs: ServiceModel, rhs: ServiceModel) -> Bool {
    return lhs.serviceUUID() == rhs.serviceUUID()
}


public class ServiceModel: NSObject {
    
    // MARK: Public properties
    
    // When a serivce is discovered on the peripheral it will be set to True.
    // When the peripheral is disconnected it will be set to False.
    public internal(set) var serviceAvailable = false {
        didSet {
            if oldValue != serviceAvailable {
                dispatch_async(dispatch_get_main_queue()) {
                    self.serviceModelDidChangeAvailableState(self.serviceAvailable)
                }
            }
        }
    }
    // When all mapped characteristics are available it will be set to True.
    // When the peripheral is disconnected it will be ste to False.
    public private(set) var serviceReady = false {
        didSet {
            if oldValue != serviceReady {
                dispatch_async(dispatch_get_main_queue()) {
                    self.serviceModelDidChangeReadyState(self.serviceReady)
                }
            }
        }
    }
    
    // MARK: Internal properties
    
    internal weak var serviceModelManager: ServiceModelManager?
    internal var valueTypeMapping = [String: Any.Type]()
    internal var transformerMapping = [String: DataTransformer]()
    internal var characteristicUUIDs: [String] {
        get {
            return Array(valueTypeMapping.keys)
        }
    }
    
    // MARK: Private properties
    
    private let map = Map()
    private var readCompletionHandlers: [String: [ReadCompletionHandler]] = [:]
	private var writeCompletionHandlers: [String: [WriteCompletionHandler]] = [:]
	
    // MARK: Initalizers
    
    required public override init() {
		super.init()
		
        map.serviceModel = self
        
        // Prefill characteristicUUIDs.
        mapping(map)
    }
    
    // MARK: Required public functions
    
    /**
     Function that needs to be subclassed.
     Return the UUID of the service it represents.
     */
    public func serviceUUID() -> String {
        fatalError("Must override this function in your subclass of `BTServiceModel`")
    }
    
    /**
     Function that needs to be subclassed.
     In this function you can create the mapping between UUID and the actual instance variable.
     */
    public func mapping(map: Map) {
        fatalError("Must override this function in your subclass of `BTServiceModel`")
    }
    
    // MARK: Helper functions
    
    /**
     Read the value of the characteristic.
        
     - parameter UUID: The UUID of the characteristic to read.
     - parameter completion: Completion block called after the read is done.
     */
    public func readValue(withUUID UUID: String, completion: ReadCompletionHandler? = nil) {
        serviceModelManager?.readValue(UUID, serviceUUID: serviceUUID())
        
        if let completion = completion {
           addReadCompletionHandler(completion, forUUID: UUID)
        }
    }
    
    /**
     Write a value to the characteristic.
     Before calling this, first set the value on your ServiceModel subclass.
        
     - parameter UUID: The UUID of the characteristic to send.
     - parameter response: Boolean to send a write with(out) response.
     */
	public func writeValue(withUUID UUID: String, response: Bool = true, completion: WriteCompletionHandler? = nil) {
        let value = getValueInServiceModel(withUUID: UUID)
        
        if let dataTransformer = transformer(forUUID: UUID) {
            let data = dataTransformer.transform(valueToData: value)
			serviceModelManager?.writeValue(data, toCharacteristicUUID: UUID, serviceUUID: serviceUUID(), response: response || completion != nil)
			
			if let completion = completion {
				addWriteCompletionHandler(completion, forUUID: UUID)
			}
        }
    }
    
    /**
     Helper method to write to multiple characteristics.
         
     - parameter UUIDs: An array of Strings of the UUIDs to write.
     - paramter response: Boolean to send a write with(out) response.
     */
    public func writeValues(withUUIDs UUIDs: [String], response: Bool = false) {
        let _ = UUIDs.map {writeValue(withUUID: $0, response: response)}
    }
    
    /**
     Called after a characteristic became available.
     It can be used to register a notify on the characteristic.
     */
    public func registerNotifyForCharacteristic(withUUID UUID: String) -> Bool {
        return false
    }
    
    /**
     Called when a characteristic became available.
     Afther this call it's possible to read and write to this characteristic.
     */
    public func characteristicBecameAvailable(withUUID UUID: String) {
        
    }
    
    /**
     Called when a value of a characteristic value is read or updated.
     Can be because of a read call or due to a notify.
     */
    public func characteristicDidUpdateValue(withUUID UUID: String) {
        
    }
    
    /**
     Called when the serviceAvailable state changed.
     */
    public func serviceModelDidChangeAvailableState(available: Bool) {
        
    }
    
    /**
     Called when the serviceReady state changed.
     */
    public func serviceModelDidChangeReadyState(ready: Bool) {
        
    }
}


extension ServiceModel {
	
	public class WriteCompletionHandler {
		private let callback: (NSError?)->()
		
		private var ran = false
		
		public required init( _ callback: (NSError?)->(), timeout: CFTimeInterval = 10) {
			self.callback = callback;
			
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(timeout * Double(NSEC_PER_SEC))), dispatch_get_main_queue()) { () -> Void in
				if !self.ran {
					self.run(NSError(domain: "net.xwaves.BLETimeout", code: 34, userInfo: [NSLocalizedDescriptionKey:NSLocalizedString("BLE write timed out.", comment: "")]))
				}
			}
		}
		
		public func run(error: NSError?) {
			ran = true
			callback(error)
		}
		
		public func cancel() {
			ran = true
		}
	}
	
	public class ReadCompletionHandler {
		private let callback: (MapValue?, NSError?)->()
		
		private var ran = false
		
		public required init( _ callback: (MapValue?, NSError?)->(), timeout: CFTimeInterval = 10) {
			self.callback = callback;
			
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(timeout * Double(NSEC_PER_SEC))), dispatch_get_main_queue()) { () -> Void in
				if !self.ran {
					self.run(nil, error: NSError(domain: "net.xwaves.BLETimeout", code: 34, userInfo: [NSLocalizedDescriptionKey:NSLocalizedString("BLE read timed out.", comment: "")]))
				}
			}
		}
		
		public func run(value: MapValue?, error: NSError?) {
			if !ran {
				ran = true
				callback(value, error)
			}
		}
		
		public func cancel() {
			ran = true
		}
	}
	
    /**
     Called by the `Map` object.
     Adds the UUID and valueType of the instance variable it represents to an dictionary.
     Also adds custom DataTransfromers to an array if they are provided.
     */
    internal func register(withUUID UUID: String, valueType: Any.Type, transformer: DataTransformer?) {
        if valueTypeMapping[UUID] == nil {
            valueTypeMapping[UUID] = valueType
        }
        if transformerMapping[UUID] == nil, let transformer = transformer {
            transformerMapping[UUID] = transformer
        }
    }
    
    /**
     Called by the `ServiceModelManager`.
     Will get the correct DataTransformer and set the value to the instance variable.
     After that is will call the completion block (if available) and other helper functions.
     */
	internal func didRead(data: NSData?, error: NSError?, withUUID UUID: String) {
		
		if let err = error {
			callReadCompletionHandlers(withValue: nil, andError: err, forUUID: UUID)
		}
		
        if let dataTransformer = transformer(forUUID: UUID) {
            let value = dataTransformer.transform(dataToValue: data)
            setValueInServiceModel(value, withUUID: UUID)
            
            // Call convenience function.
            characteristicDidUpdateValue(withUUID: UUID)
            
            // Call all existing completion blocks for this read.
			callReadCompletionHandlers(withValue: value, andError: nil, forUUID: UUID)
		} else {
			callReadCompletionHandlers(withValue: nil, andError: NSError(domain: "com.xwaves.BLE", code: 33, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("Invalid data type for transformer.", comment: "")]), forUUID: UUID)
		}
    }
	
	/**
	Called by the `ServiceModelManager`.
	Will call the completion block (if available) and other helper functions.
	*/
	internal func didWrite(error: NSError?, withUUID UUID: String) {
		// Call all existing completion blocks for this read.
		callWriteCompletionHandlers(withError: error, forUUID: UUID)
	}
	
    /**
     Called by the `ServiceModelManager` once a characteristic became available.
     */
    internal func characteristicAvailable(withUUID UUID: String) {
        if !serviceReady && allCharacteristicsAvailable() {
            serviceReady = true
        }
        
        characteristicBecameAvailable(withUUID: UUID)
    }
    
    /**
     Reset the `ServiceModel` and make it unavailable.
     Called when the connection is lost with the peripheral.
     */
    internal func resetService() {
        serviceReady = false
        serviceAvailable = false
    }
    
    // MARK: Private functions
    
    /**
     Return the correct DataTransformer.
     A custom DataTransformer if provided.
     Or a default DataTransformer if the type is supported.
     */
    private func transformer(forUUID UUID: String) -> DataTransformer? {
        // Return custom transformer if available.
        if let transformer = transformerMapping[UUID] {
            return transformer
        }
        
        // Get the a default transformer based on the type of the property.
        guard let valueType = valueType(forUUID: UUID) else {
            return nil
        }
        if valueType == String?.self || valueType == String.self {
            return StringDataTransformer()
        } else if valueType == UInt8?.self || valueType == UInt8.self {
            return UInt8DataTransformer()
        } else if valueType == UInt16?.self || valueType == UInt16.self {
            return UInt16DataTransformer()
        } else if valueType == UInt32?.self || valueType == UInt32.self {
            return UInt32DataTransformer()
        } else if valueType == NSData?.self || valueType == NSData.self {
            return NSDataDataTransformer()
		}
        return nil
    }
    
    /**
     Returns the valueType of a characteristic.
     */
    private func valueType(forUUID UUID: String) -> Any.Type? {
        return valueTypeMapping[UUID]
    }
    
    /**
     Setting a value on the ServiceModel.
     It will place the value in the `Map` object before calling the mapping function.
     The mapping function will loop through all instance variables.
     Once it matches the same UUID it will copy the value to the actual instance variable.
     */
    private func setValueInServiceModel(value: MapValue?, withUUID UUID: String) {
        // Store UUID and value in Map.
        map.setMapUUID = UUID
        map.setMapValue = value
        
        // Call mapping function.
        mapping(map)
        
        // Clean UUID and value from map to prevent errors.
        map.setMapUUID = nil
        map.setMapValue = nil
    }
    
    /**
     Get a value from the ServiceModel.
     It will register wich value it should get on the `Map` object.
     The mapping function will loop through all the instance variables.
     Once it matches the same UUID it will get the value and place it in the `Map` object.
     The value of the `Map` object will be returned.
     */
    private func getValueInServiceModel(withUUID UUID: String) -> MapValue? {
        // Register the correct UUID to get the value from.
        map.getMapUUID = UUID
        
        // Call mapping function.
        mapping(map)
        
        // Clean UUID and get the value.
        map.getMapUUID = nil
        return map.getMapValue
    }
    
    /**
     Add a completion handler to the Dictionary.
     Multiple completion blocks can be registered for the same UUID.
     */
    private func addReadCompletionHandler(completionHandler: ReadCompletionHandler, forUUID UUID: String) {
        if var completionHandlers = readCompletionHandlers[UUID] {
            completionHandlers.append(completionHandler)
            readCompletionHandlers[UUID] = completionHandlers
        } else {
            readCompletionHandlers[UUID] = [completionHandler]
        }
    }
    
    /**
     Call all registered completion blocks for that UUID.
     Multiple completion blocks can be called for the same UUID.
     */
	private func callReadCompletionHandlers(withValue value: MapValue?, andError error: NSError?, forUUID UUID: String) {
        guard let completionHandlers = readCompletionHandlers[UUID] else {
            return
        }
        
        for completionHandler in completionHandlers {
            completionHandler.run(value, error: error)
        }
		
        readCompletionHandlers[UUID] = nil
    }
	
	/**
	Add a completion handler to the Dictionary.
	Multiple completion blocks can be registered for the same UUID.
	*/
	private func addWriteCompletionHandler(completionHandler: WriteCompletionHandler, forUUID UUID: String) {
		if var completionHandlers = writeCompletionHandlers[UUID] {
			completionHandlers.append(completionHandler)
			writeCompletionHandlers[UUID] = completionHandlers
		} else {
			writeCompletionHandlers[UUID] = [completionHandler]
		}
	}
	
	/**
	Call all registered completion blocks for that UUID.
	Multiple completion blocks can be called for the same UUID.
	*/
	private func callWriteCompletionHandlers(withError error: NSError?, forUUID UUID: String) {
		guard let completionHandlers = writeCompletionHandlers[UUID] else {
			return
		}
		
		for completionHandler in completionHandlers {
			completionHandler.run(error)
		}
		
		writeCompletionHandlers.removeValueForKey(UUID)
	}
	
    /**
     Check if all characteristics are available.
     */
    private func allCharacteristicsAvailable() -> Bool {
        for characteristicUUID in characteristicUUIDs {
            if serviceModelManager?.characteristicAvailable(characteristicUUID, serviceUUID: serviceUUID()) == false {
                return false
            }
        }
        return true
    }
}
