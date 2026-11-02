import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: post.swift snapshot <dir> | action <selector>\n".utf8))
    exit(2)
}
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("dev.dreamder.\(arguments[0])"),
    object: arguments[1],
    userInfo: nil,
    deliverImmediately: true
)
