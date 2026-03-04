import Foundation

public enum S3Error: Error, Sendable {
    case noSuchBucket
    case noSuchKey
    case bucketAlreadyExists
    case bucketNotEmpty
    case invalidBucketName
    case invalidRequest
    case accessDenied
    case authenticationRequired
    case internalError(String)

    var code: String {
        switch self {
        case .noSuchBucket:            return "NoSuchBucket"
        case .noSuchKey:               return "NoSuchKey"
        case .bucketAlreadyExists:     return "BucketAlreadyExists"
        case .bucketNotEmpty:          return "BucketNotEmpty"
        case .invalidBucketName:       return "InvalidBucketName"
        case .invalidRequest:          return "InvalidRequest"
        case .accessDenied:            return "AccessDenied"
        case .authenticationRequired:  return "AuthenticationRequired"
        case .internalError:           return "InternalError"
        }
    }

    var httpStatus: Int {
        switch self {
        case .noSuchBucket, .noSuchKey:  return 404
        case .bucketAlreadyExists:        return 409
        case .bucketNotEmpty:             return 409
        case .invalidBucketName:          return 400
        case .invalidRequest:             return 400
        case .accessDenied:               return 403
        case .authenticationRequired:     return 401
        case .internalError:              return 500
        }
    }

    var message: String {
        switch self {
        case .noSuchBucket:            return "The specified bucket does not exist."
        case .noSuchKey:               return "The specified key does not exist."
        case .bucketAlreadyExists:     return "The requested bucket name is not available."
        case .bucketNotEmpty:          return "The bucket you tried to delete is not empty."
        case .invalidBucketName:       return "The specified bucket is not valid."
        case .invalidRequest:          return "The request is invalid."
        case .accessDenied:            return "Access Denied."
        case .authenticationRequired:  return "Authentication required."
        case .internalError(let m):    return m
        }
    }
}
