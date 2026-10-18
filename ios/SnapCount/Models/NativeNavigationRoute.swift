import Foundation

enum NativeInboxRoute: Hashable {
    case category(filter: NativeInboxFilter)
    case staging(recordId: String)
    case record(reference: String)
}

struct NativeRecordRoute: Hashable {
    let reference: String
}

struct NativeDomainDrillRoute: Hashable {
    let domain: AppDomain
    let dateKey: String
}

struct NativeDomainRoute: Hashable {
    let domainId: String
}

struct NativeAccountRoute: Hashable {
    let accountId: String
}
