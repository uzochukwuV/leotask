// The 'test_usdcx_atomation' test program.
import usdcx_atomation.aleo;
program test_usdcx_atomation.aleo {
    @test
    script test_it() {
        let result: u32 = usdcx_atomation.aleo/main(1u32, 2u32);
        assert_eq(result, 3u32);
    }

    @test
    @should_fail
    transition do_nothing() {
        let result: u32 = usdcx_atomation.aleo/main(2u32, 3u32);
        assert_eq(result, 3u32);
    }

    @noupgrade
    async constructor() {}
}
