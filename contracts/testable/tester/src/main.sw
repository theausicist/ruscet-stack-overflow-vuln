// SPDX-License-Identifier: Apache-2.0
contract;
 
abi Tester {
    fn fail_implicity();
}

enum Error {
    FailImplicitly: ()
}

struct MyLog1 {
	value: u64
}

struct MyLog2 {
	is_true: bool
}

impl Tester for Contract {
    fn fail_implicity() {
		log(MyLog1 { value: 1 });
		log(MyLog2 { is_true: true });
        require(false, Error::FailImplicitly);
    }
}
 