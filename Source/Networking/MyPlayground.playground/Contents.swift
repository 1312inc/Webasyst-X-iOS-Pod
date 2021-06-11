import Foundation

class TestClassOne {
    
    var a: Int = 1
    
    var b: Int = 1
    
    func plus(a: Int, b: Int) -> Int {
        let c = a + b
        return c
    }

}

class TestClassTwo: TestClassOne {
    var c: Int = 4
    var d: Int = 6
    
    func plus(a: Int, b: Int) -> Int {
        let c = a - b
        return c
    }
    
}

class TestClassThree {
    
    let testClass: TestClassTwo!
    
    init(test: TestClassTwo) {
        self.testClass = test
    }
    
    lazy var c = self.testClass.plus(a: 10, b: 2)
    
    func show() {
        print(testClass.a, testClass.b, testClass.c, testClass.d, c)
    }
    
}

TestClassThree(test: TestClassTwo()).show()

