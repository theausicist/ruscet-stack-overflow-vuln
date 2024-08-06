// SPDX-License-Identifier: Apache-2.0
contract;

mod errors;
use std::{
    block::timestamp,
    context::*,
	identity::Identity,
    revert::require,
};
use std::auth::msg_sender;
use ::errors::*;

abi Callee {
	fn get_sender() -> (bool, bool);

	#[storage(read, write)]
    fn call_me_fail();
}

storage {
	one: u64 = 1,
	two: u64 = 2,
	three: u64 = 3,
}

impl Callee for Contract {
	fn get_sender() -> (bool, bool) {
		(true, false)
	}

    #[storage(read, write)]
    fn call_me_fail() {
		storage.one.write(60);

        require(
            false, 
            Error::CalleeError5
        );

		storage.two.write(49);
		storage.three.write(49);
    }
}