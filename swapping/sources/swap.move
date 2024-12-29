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

    public entry fun add_liquidity<X, Y>(sender: &signer, x_amount : u64,y_amount: u64) acquires Pair{
        // Make sure the pair exists
        assert!(exists<Pair<X, Y>>(@swap_account), 1000);

        // Borrow the pair data from global storage
        let pair = borrow_global_mut<Pair<X, Y>>(@swap_account);

        // Convert the amount of tokens to u128 to prevent overflow during calculatoins
        let x_amount = (x_amount as u128) ;
        let y_amount = (y_amount as u128) ;

        // Get the current reserves for token X and Y
        let x_reserve = (coin::value(&pair.x_coin) as u128);
        let y_reserve = (coin::value(&pair.y_coin) as u128);

        // Calculating the optimal amount of Y to be added given the amount of X
        let y_amount_optimal = quote(x_amount, x_reserve, y_reserve);

        // Choose the smaller of the actual Y amount and the optimal Y amount
        if (y_amount_optimal <= y_amount){
            y_amount = y_amount_optimal;
        }else{
            let x_amount_optimal = quote(y_amount, y_reserve, x_reserve);
            x_amount = x_amount_optimal;
        };

        // Withdraw X and Y tokens from the sender's account
        let x_amount_coin = coin::withdraw<X>(sender, (x_amount as u64));
        let y_amount_coin = coin::withdraw<Y>(sender, (y_amount as u64));

        // Deposit the withdraw tokens into the Pair
        coin::merge(&mut pair.x_coin, x_amount_coin);
        coin::merge(&mut pair.y_coin, y_amount_coin);

        // Calculate the liquidity to be minted and mint Lp tokens accordingly
        let liquidity;
        let total_supply = *option::borrow(&coin::supply<LP<X, Y>>());
        if (total_supply == 0){
            liquidity = sqrt(((x_amount * y_amount) as u128)) - MINIMUM_LIQUIDITY;
            let lp_locked = coin::mint(MINIMUM_LIQUIDITY, &pair.lp_mint);
            coin::merge(&mut pair.lp_locked, lp_locked);
        }else{
            liquidity = (min(
                Math::mul_div(x_amount, total_supply, x_reserve),
                Math::mul_div(y_amount, total_supply, y_reserve),
            ) as u64);
        };

        // Mint the liquidty and deposit it into the sender's account
        let lp_coin = coin::mint<LP<X, Y>>(liquidity, &pair.lp_mint);
        let addr = address_of(sender);
        if (!coin::is_account_registered<LP<X, Y>>(addr)){
            coin::register<LP<X, Y>>(sender);
        };
        coin::deposit(addr, lp_coin);
    }

    public entry fun remove_liquidity<X, Y>(sender: &signer, liquidity: u64) acquires Pair{
        // Make sure the pair exists
        assert!(exists<Pair<X, Y>>(@swap_account), 1000);

        // Borrow the pair data from global storage
        let pair = borrow_global_mut<Pair<X, Y>>(@swap_account);

        // Withdraw liquidity from the sender's account
        let liquidity_coin = coin::withdraw<LP<X, Y>>(sender, liquidity);
        coin::burn(liquidity_coin, &pair.lp_burn);

        // Get the total supply of LP tokens, and the current reserves for token X and Y
        let total_supply = *option::borrow(&coin::supply<LP<X, Y>>());
        let x_reserve = (coin::value(&pair.x_coin) as u128);
        let y_reserve = (coin::value(&pair.y_coin) as u128);

        // Calculate the amount of X and Y to be withdrawn
        let x_amount = Math::mul_div((liquidity as u128), x_reserve, total_supply);
        let y_amount = Math::mul_div((liquidity as u128), y_reserve, total_supply);

        // Extract the amounts of X and Y tokens from the pair
        let x_amount_coin = coin::extract<X>(&mut pair.x_coin, (x_amount as u64));
        let y_amount_coin = coin::extract<Y>(&mut pair.y_coin, (y_amount as u64));

        // Deposit the extracted tokens back into the sender's account
        coin::deposit(address_of(sender), x_amount_coin);
        coin::deposit(address_of(sender), y_amount_coin);
    }

    public entry fun swap<X, Y>(sender: &signer, amount_in: u64) acquires Pair{
        // Make sure the pair exists
        assert!(exists<Pair<X, Y>>(@swap_account), 1000);

        // Borrow the pair data from global storage
        let pair = borrow_global_mut<Pair<X, Y>>(@swap_account);

        // Withdraw the input token X from the sender's account
        let coin_in = coin::withdraw<X>(sender, amount_in);

        // Register the sender's account for token Y if not already registered
        if (!coin::is_account_registered<Y>(address_of(sender))){
            coin::register<Y>(sender);
        };

        // Get the current reserves for token X and Y
        let x_reserve = (coin::value(&pair.x_coin) as u128);
        let y_reserve = (coin::value(&pair.y_coin) as u128);

        // Calculate the amount of output token Y to be received
        let amount_out = get_amount_out((amount_in as u128), x_reserve, y_reserve);

        // Deposit the input token X into the pair
        coin::merge(&mut pair.x_coin, coin_in);

        let amount_out_coin = coin::extract(&mut pair.y_coin, (amount_out as u64));

        // Deposit the received token Y back into the sender's account
        coin::deposit(address_of(sender), amount_out_coin);
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
    public fun min(x:u128, y:u128):u128{
        if (x < y){
            x
        }else{
            y
        }
    }
    public fun sqrt(x:u128):u64{
        let z = (x + 1) / 2;
        let y = x;
        while (z < y){
            y = z;
            z = (x / z + z) / 2;
        };
        (y as u64)
    }
    public fun mul_div(x_amount:u128, x_reserve:u128, y_reserve:u128) : u128{
        x_amount * y_reserve / x_reserve
    }
}