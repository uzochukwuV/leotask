program test_syntax.aleo {
    async transition test_func() -> Future {
        return finalize_test_func();
    }
    async function finalize_test_func() {
        assert(true);
    }
}
