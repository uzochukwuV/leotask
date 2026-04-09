import token_registry.aleo;

program test_v4.aleo {
    fn test_func() -> Final {
        let transfer_future: Final = token_registry.aleo/transfer_public_as_signer(0field, self.address, 100u128);
        return final { 
            transfer_future.run();
        };
    }
}
