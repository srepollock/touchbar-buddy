import Darwin
import Foundation
import TouchBuddyCore

let input = FileHandle.standardInput.readDataToEndOfFile()
_ = runHook(
    stdin: input,
    environment: ProcessInfo.processInfo.environment,
    store: SessionStore(directory: TouchBuddyPaths.resolve().sessions),
    claudePID: findClaudeAncestorPID(startingAt: getppid()),
    now: Date()
)
exit(0)
