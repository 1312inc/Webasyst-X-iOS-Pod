import Foundation

final class Decoder {
    
    private let dictionary: [Character] = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"]
    
    private let shift: Int!
    
    init(_ shift: Int) {
        self.shift = shift
    }

    func encode(with word: String) -> String {
        var result: String = ""
        for char in word {
            for index in 0 ..< dictionary.count {
                if char.lowercased() == dictionary[index].lowercased() {
                    if index + self.shift <= dictionary.count - 1 {
                        result.append(dictionary[index + shift])
                    } else {
                        let minus = dictionary.count - index
                        result.append(dictionary[shift - minus])
                    }
                }
            }
        }
        return result
    }

    func decode(_ encodeWord: String) -> String {
        var result: String = ""
        for char in encodeWord {
            for index in 0 ..< dictionary.count {
                if char.lowercased() == dictionary[index].lowercased() {
                    if index - self.shift < 0 {
                        let difference = -(index - shift)
                        result.append(dictionary[dictionary.count - difference])
                    } else {
                        result.append(dictionary[index - shift])
                    }
                }
            }
        }
        return result
    }
}

let shift: Int = 3
let stroka: String = "privet medved"

let encodeString = Decoder(shift).encode(with: stroka)
print(encodeString)
let normalString = Decoder(shift).decode(encodeString)
print(normalString)
