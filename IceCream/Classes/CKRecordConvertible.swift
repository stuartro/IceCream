//
//  Object+CKRecord.swift
//  IceCream
//
//  Created by 蔡越 on 11/11/2017.
//

import Foundation
import CloudKit
import RealmSwift

// MARK: - CKRECORDCONVERTIBLE
/// Use `CKRecordConvertible` to “mark” your Realm-based model types (i.e. `Object` subclasses)
/// as being convertable to `CKRecord` instances to permit syncing to iCloud.
///
/// The extension-provided implementation of `CKRecordConvertible` provides the ability
/// to convert your Realm-based model types into `CKRecord` instances.
/// - Attention:
///   􀃮 Be aware that (at present) `CKRecordConvertible`’s implementation (see the default extension)
///      does *not* support Realm `List`s of non-primitive types. This means that a property on some model
///      class of type `List<Int>`, say, *will* correctly sync using IceCream, while a property of type
///      `List<SomeOtherModelClass>` will *not* sync (at all). See the main documentation for a solution.
public protocol CKRecordConvertible {
    static var recordType: String { get }
    static var zoneID: CKRecordZone.ID { get }
    static var databaseScope: CKDatabase.Scope { get }
    
   /// The recordID used to identify this model object in iCloud.
    var recordID: CKRecord.ID { get }
   
   /// Returns a `CKRecord` instance that will be used to “upload” this `CKRecordConvertible`
   /// (which is typically one of your Realm-based model classes) to iCloud.
   ///
   /// This is where the the upload-part of the “heavy lifting” is done, converting the class
   /// that adopts `CKRecordConvertible` into a `CKRecord` suitable for uploading to iCloud.
    var record: CKRecord { get }

   /// `true` if this model object has been (soft) deleted, or `false` otherwise.
    var isDeleted: Bool { get }
}

// MARK: - CKRECORDCONVERTIBLE DEFAULT IMPLEMENTATION
extension CKRecordConvertible where Self: Object {
    
    public static var databaseScope: CKDatabase.Scope {
        return .private
    }
    
    public static var recordType: String {
        return className()
    }
    
    public static var zoneID: CKRecordZone.ID {
        switch Self.databaseScope {
        case .private:
            return CKRecordZone.ID(zoneName: "\(recordType)sZone", ownerName: CKCurrentUserDefaultName)
        case .public:
            return CKRecordZone.default().zoneID
        default:
            fatalError("Shared Database is not supported now")
        }
    }
    
    /// recordName : this is the unique identifier for the record, used to locate records on the database. We can create our own ID or leave it to CloudKit to generate a random UUID.
    /// For more: https://medium.com/@guilhermerambo/synchronizing-data-with-cloudkit-94c6246a3fda
    public var recordID: CKRecord.ID {
        guard let sharedSchema = Self.sharedSchema() else {
            fatalError("No schema settled. Go to Realm Community to seek more help.")
        }
        
        guard let primaryKeyProperty = sharedSchema.primaryKeyProperty else {
            fatalError("You should set a primary key on your Realm object")
        }
        
        switch primaryKeyProperty.type {
        case .string:
            if let primaryValueString = self[primaryKeyProperty.name] as? String {
                // For more: https://developer.apple.com/documentation/cloudkit/ckrecord/id/1500975-init
                assert(primaryValueString.allSatisfy({ $0.isASCII }), "Primary value for CKRecord name must contain only ASCII characters")
                assert(primaryValueString.count <= 255, "Primary value for CKRecord name must not exceed 255 characters")
                assert(!primaryValueString.starts(with: "_"), "Primary value for CKRecord name must not start with an underscore")
                return CKRecord.ID(recordName: primaryValueString, zoneID: Self.zoneID)
            } else {
                assertionFailure("\(primaryKeyProperty.name)'s value should be String type")
            }
        case .int:
            if let primaryValueInt = self[primaryKeyProperty.name] as? Int {
                return CKRecord.ID(recordName: "\(primaryValueInt)", zoneID: Self.zoneID)
            } else {
                assertionFailure("\(primaryKeyProperty.name)'s value should be Int type")
            }
        default:
            assertionFailure("Primary key should be String or Int")
        }
        fatalError("Should have a reasonable recordID")
    }
    
   /// Returns a `CKRecord` instance that will be used to “upload” this `CKRecordConvertible`
   /// (which is typically one of your Realm-based model classes) to iCloud.
   ///
   /// This is where the the upload-part of the “heavy lifting” is done, converting the class
   /// that adopts `CKRecordConvertible` into a `CKRecord` suitable for uploading to iCloud.
   ///
   /// **Implementation Notes:**
   /// Simultaneously init CKRecord with zoneID and recordID, thanks to this guy:
   /// https://stackoverflow.com/questions/45429133/how-to-initialize-ckrecord-with-both-zoneid-and-recordid
    public var record: CKRecord {
        let r = CKRecord(recordType: Self.recordType, recordID: recordID)
        let properties = objectSchema.properties
        for prop in properties {
            
            let item = self[prop.name]
            
            if prop.isArray {
                switch prop.type {
                case .int:
                    guard let list = item as? List<Int>, !list.isEmpty else { break }
                    let array = Array(list)
                    r[prop.name] = array as CKRecordValue
                case .string:
                    guard let list = item as? List<String>, !list.isEmpty else { break }
                    let array = Array(list)
                    r[prop.name] = array as CKRecordValue
                case .bool:
                    guard let list = item as? List<Bool>, !list.isEmpty else { break }
                    let array = Array(list)
                    r[prop.name] = array as CKRecordValue
                case .float:
                    guard let list = item as? List<Float>, !list.isEmpty else { break }
                    let array = Array(list)
                    r[prop.name] = array as CKRecordValue
                case .double:
                    guard let list = item as? List<Double>, !list.isEmpty else { break }
                    let array = Array(list)
                    r[prop.name] = array as CKRecordValue
                case .data:
                    guard let list = item as? List<Data>, !list.isEmpty else { break }
                    let array = Array(list)
                    r[prop.name] = array as CKRecordValue
                case .date:
                    guard let list = item as? List<Date>, !list.isEmpty else { break }
                    let array = Array(list)
                    r[prop.name] = array as CKRecordValue
                default:
                    let typeName = String(reflecting: type(of: self))
                    print("⚠️ WARNING: Realm property \(typeName)).\(prop.name) is not supported by IceCream")
                    break
                    /// Other inner types of List is not supported yet
                }
                continue
            }
            
            switch prop.type {
            case .int, .string, .bool, .date, .float, .double, .data:
                r[prop.name] = item as? CKRecordValue
            case .object:
                guard let objectName = prop.objectClassName else { break }
                // If object is CreamAsset, set record with its wrapped CKAsset value
                if objectName == CreamAsset.className(), let creamAsset = item as? CreamAsset {
                    r[prop.name] = creamAsset.asset
                } else if let owner = item as? CKRecordConvertible {
                    // Handle to-one relationship: https://realm.io/docs/swift/latest/#many-to-one
                    // So the owner Object has to conform to CKRecordConvertible protocol
                    r[prop.name] = CKRecord.Reference(recordID: owner.recordID, action: .none)
                } else {
                    /// Just a warm hint:
                    /// When we set nil to the property of a CKRecord, that record's property will be hidden in the CloudKit Dashboard
                    r[prop.name] = nil
                }
                // To-many relationship is not supported yet.
            default:
                break
            }
        }
        return r
    }
}
