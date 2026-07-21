import Foundation

enum NativeInboxRoute: Hashable {
    case staging(recordId: String)
    case record(reference: String)
}

struct NativeRecordRoute: Hashable {
    let reference: String
}

struct NativeDomainRoute: Hashable {
    let domainId: String
}

struct NativeAccountRoute: Hashable {
    let accountId: String
}
