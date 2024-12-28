// Module for implementing a simple swap protocol for generating LP tokens, creating a pool, adding/removing liquidity, and swapping tokens.
module swap_account::Swap{
    // Import required modules and libraries
    use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability};
    use std::string;
    use std::string::String;
    use std::option;
    use swap_account::Math::{sqrt, min};
    use std::signer::address_of;
    use swap_account::Math;

    // Constants for minimum liquidity required in LP tokens
    const MINIMUM_LIQUIDITY:u64 = 1000;

    // Define a phantom struct LP with genenric types X and Y to represent LP tokens for token pair X-Y
    struct LP<phantom X, phantom Y> {}

    // Define a struct Pair with generic types X and Y representing a token pair with its related data
    struct Pair<phantom X, phantom Y> has key {
        x_coin : Coin<X>,
        y_coin : Coin<Y>,
        lp_locked : Coin <LP<X,Y>>,
        lp_mint: MintCapability<LP<X, Y>>,
        lp_burn : BurnCapability<LP<X, Y>>,
    }

    // Function to generate LP token name symbol for a given pair X-Y
    public fun generate_lp_name_symbol<X, Y>(): String {
        let lp_name_symbol = string::utf8(b"");
        string::append_utf8(&mut lp_name_symbol, b"LP");
        string::append_utf8(&mut lp_name_symbol, b"-");
        string::append(&mut lp_name_symbol, coin::symbol<X>());
        string::append_utf8(&mut lp_name_symbol, b"-");
        string::append(&mut lp_name_symbol, coin::symbol<Y>());
        lp_name_symbol
    }

    // Function to create a new pool for token pair X-Y
    public entry fun create_pool<X, Y>(sender: &signer) {
        // Check if the pair already exists (a pair for X-Y or Y-X)
        assert!(!pair_exists<X, Y>(@swap_account), 1000);

        let lp_name_symbol = generate_lp_name_symbol<X, Y>();

        let (lp_burn, lp_freeze, lp_mint) = coin::initialize<LP<X, Y>>(
            sender,
            lp_name_symbol,
            lp_name_symbol,
            6, // Number of decimal places for the LP token
            true, // LP token is fungible
        );

        coin::destroy_freeze_cap(lp_freeze);

        move_to(
            sender,
            Pair<X, Y> {
                x_coin: coin::zero<X>(),
                y_coin: coin::zero<Y>(),
                lp_locked: coin::zero<LP<X, Y>>(),
                lp_mint,
                lp_burn,
            },
        );

    }

    public fun pair_exists<X, Y>(addr: address) : bool {
        exists<Pair<X, Y>>(addr) || exists<Pair<Y, X>>(addr)
    }

    public fun quote(x_amount:u128, x_reserve:u128, y_reserve:u128) : u128 {
        Math::mul_div(x_amount, y_reserve, x_reserve)
    }

    public fun get_amount_out(amount_in:u128, reserve_in:u128, reserve_out:u128) : u128 {
        let amount_in_with_fee = amount_in * 997;
        let numerator = amount_in_with_fee * reserve_out;
        let denominator = reserve_in * 1000 + amount_in_with_fee;
        numerator / denominator
    }

    public fun get_coin<X, Y>():(u64,u64) acquires Pair {
        let pair = borrow_global<Pair<X, Y>>(@swap_account);
        (coin::value(&pair.x_coin), coin::value(&pair.y_coin))
    }
}

module swap_account::Math{
    public fun min(){}
    public fun sqrt(){}
    public fun mul_div(x_amount:u128, x_reserve:u128, y_reserve:u128) : u128{
        x_amount * y_reserve / x_reserve
    }
}