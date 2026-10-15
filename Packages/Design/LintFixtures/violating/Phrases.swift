import SwiftUI

struct BadPhrases: View {
    let host = "api.example.com"
    let source = "Studio"
    let n = 3
    let m = 40

    var body: some View {
        VStack {
            Text("Saved") // lint-expect: status-phrase
            Text("saved") // lint-expect: status-phrase
            Text("Saving...") // lint-expect: status-phrase
            Text("Ready · indexing continues") // lint-expect: status-phrase
            Text("Sending to \(host)") // lint-expect: status-phrase
            Text("Waiting for \(source)") // lint-expect: status-phrase
            Text("Indexing \(n) of \(m) chapters") // lint-expect: status-phrase
            Text("Indexing \(n) of \(m) chapter") // lint-expect: status-phrase
            Text("\(host) · hosted") // lint-expect: status-phrase
            Text("Upload finished. Not saved · your text is still here") // lint-expect: status-phrase
            Text("Imported into Sylvia") // lint-expect: status-phrase
            Text(verbatim: "Delete record and thoughts") // lint-expect: status-phrase
            Text("Done") // lint-expect: forbidden-phrase
            Text("Thinking…") // lint-expect: forbidden-phrase
            Text("Thinking...") // lint-expect: forbidden-phrase
            Text("ERROR") // lint-expect: forbidden-phrase
            Text("The AI read your book") // lint-expect: forbidden-phrase
            Text(verbatim: "Whole book") // lint-expect: forbidden-phrase
            Text("We searched everything for you") // lint-expect: forbidden-phrase
            Text("Free with your subscription \(n)") // lint-expect: forbidden-phrase
        }
    }
}

let raw = #"Record only"# // lint-expect: status-phrase
let escaped = "Not on this device · from \"Studio\"" // lint-expect: status-phrase
