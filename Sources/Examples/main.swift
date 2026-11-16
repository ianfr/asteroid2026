import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "bennu"
do {
    if command == "bennu" {
        let output = arguments.count > 1 ? arguments[1] : "OUT/desktop"
        let steps = arguments.count > 2 ? Int(arguments[2]) ?? 2000 : 2000
        try run_bennu_two_impactors(output_directory: output, steps: steps)
    }
    else if command == "cohesion" {
        run_cohesion_calibration()
    }
    else {
        print("unknown example: \(command) (try bennu or cohesion)")
        exit(1)
    }
}
catch {
    print("example failed: \(error)")
    exit(1)
}
