// The 'test_hello_contract' test program.
import hello_contract.aleo;
program test_hello_contract.aleo {
    @test
    fn test_main_success() {
        let result: u32 = hello_contract.aleo::main(2u32, 3u32);
        assert_eq(result, 5u32);
    }

    @test
    @should_fail
    fn test_main_fails() {
        let result: u32 = hello_contract.aleo::main(2u32, 3u32);
        assert_eq(result, 3u32);
    }

    @noupgrade
    constructor() {}
}
