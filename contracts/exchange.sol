// =================== CS251 DEX Project =================== // 
//        @authors: Simon Tao '22, Mathew Hogan '22          //
// ========================================================= //    
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '../interfaces/erc20_interface.sol';
import '../libraries/safe_math.sol';
import './token.sol';


contract TokenExchange {
    using SafeMath for uint;
    address public admin;

    address tokenAddr = 0xD23CaA5A3DC00fB50E6084b40A5329dE07942AA0;  // : Paste token contract address here.
    Smile private token = Smile(tokenAddr);         // : Replace "Token" with your token class.             

    // Liquidity pool for the exchange
    uint public token_reserves = 0;
    uint public eth_reserves = 0;
    mapping(address => uint) public stakes;
    uint public total_stakes = 0;

    // Constant: x * y = k
    uint public k;
    
    // liquidity rewards
    uint private swap_fee_numerator = 0;       // TODO Part 5: Set liquidity providers' returns.
    uint private swap_fee_denominator = 100;
    
    event AddLiquidity(address from, uint amount);
    event RemoveLiquidity(address to, uint amount);
    event Received(address from, uint amountETH);

    constructor() 
    {
        admin = msg.sender;
    }
    
    modifier AdminOnly {
        require(msg.sender == admin, "Only admin can use this function!");
        _;
    }

    // Used for receiving ETH
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
    fallback() external payable{}

    // Function createPool: Initializes a liquidity pool between your Token and ETH.
    // ETH will be sent to pool in this transaction as msg.value
    // amountTokens specifies the amount of tokens to transfer from the liquidity provider.
    // Sets up the initial exchange rate for the pool by setting amount of token and amount of ETH.
    function createPool(uint amountTokens)
        external
        payable
        AdminOnly
    {
        // require pool does not yet exist
        require (token_reserves == 0, "Token reserves was not 0");
        require (eth_reserves == 0, "ETH reserves was not 0.");

        // require nonzero values were sent
        require (msg.value > 0, "Need ETH to create pool.");
        require (amountTokens > 0, "Need tokens to create pool.");

        token.transferFrom(msg.sender, address(this), amountTokens);
        eth_reserves = msg.value;
        token_reserves = amountTokens;
        k = eth_reserves.mul(token_reserves);

        // : Keep track of the initial liquidity added so the initial provider
        //          can remove this liquidity
        stakes[msg.sender] = msg.value;
        total_stakes = msg.value;
    }

    // ============================================================
    //                    FUNCTIONS TO IMPLEMENT
    // ============================================================
    /* Be sure to use the SafeMath library for all operations! */
    
    // Function priceToken: Calculate the price of your token in ETH.
    // You can change the inputs, or the scope of your function, as needed.
    function priceToken() 
        public 
        view
        returns (uint)
    {
        /******* : Implement this function *******/
        /* HINTS:
            Calculate how much ETH is of equivalent worth based on the current exchange rate.
        */
        return eth_reserves.div(token_reserves);
    }

    // Function priceETH: Calculate the price of ETH for your token.
    // You can change the inputs, or the scope of your function, as needed.
    function priceETH()
        public
        view
        returns (uint)
    {
        /******* : Implement this function *******/
        /* HINTS:
            Calculate how much of your token is of equivalent worth based on the current exchange rate.
        */
        return token_reserves.div(eth_reserves);
    }


    /* ========================= Liquidity Provider Functions =========================  */ 

    // Function addLiquidity: Adds liquidity given a supply of ETH (sent to the contract as msg.value)
    // You can change the inputs, or the scope of your function, as needed.
    function addLiquidity() 
        external 
        payable
    {
        /******* : Implement this function *******/
        /* HINTS:
            Calculate the liquidity to be added based on what was sent in and the prices.
            If the caller possesses insufficient tokens to equal the ETH sent, then transaction must fail.
            Update token_reserves, eth_reserves, and k.
            Emit AddLiquidity event.
        */
        // transfer tokens to this exchange
        uint equivalentToken = priceETH().mul(msg.value);
        require(token.allowance(msg.sender, address(this)) >= equivalentToken, "Insuffecient token.");
        token.transferFrom(msg.sender, address(this), equivalentToken);
        // update reserves and k 
        eth_reserves = eth_reserves.add(msg.value);
        token_reserves = token_reserves.add(equivalentToken);
        k = eth_reserves.mul(token_reserves);
        // increase the sender's stakes
        stakes[msg.sender] = stakes[msg.sender].add(msg.value);
        total_stakes = total_stakes.add(msg.value);
        // emit the event
        emit AddLiquidity(msg.sender, msg.value);
    }


    // Function removeLiquidity: Removes liquidity given the desired amount of ETH to remove.
    // You can change the inputs, or the scope of your function, as needed.
    function removeLiquidity(uint amountETH)
        public 
        payable
    {
        /******* TODO: Implement this function *******/
        /* HINTS:
            Calculate the amount of your tokens that should be also removed.
            Transfer the ETH and Token to the provider.
            Update token_reserves, eth_reserves, and k.
            Emit RemoveLiquidity event.
        */
        // verify that the sender is entitled to enough funds
        require(amountETH > 0, "Requested amount of ETH must be positive");
        uint neededStakes = amountETH.mul(total_stakes.div(eth_reserves));
        require(neededStakes <= stakes[msg.sender], "User is not entitled to enough ETH");
        // update the state of this exchange to reflect the withdrawal
        stakes[msg.sender] = stakes[msg.sender].sub(neededStakes);
        total_stakes = total_stakes.sub(neededStakes);
        uint equivalentToken = priceETH().mul(amountETH);
        eth_reserves = eth_reserves.sub(amountETH);
        token_reserves = token_reserves.sub(equivalentToken);
        k = eth_reserves.mul(token_reserves);
        // transfer funds
        payable(msg.sender).transfer(amountETH);
        token.transfer(msg.sender, equivalentToken);
        // emit the event
        emit RemoveLiquidity(msg.sender, amountETH);
    }

    // Function removeAllLiquidity: Removes all liquidity that msg.sender is entitled to withdraw
    // You can change the inputs, or the scope of your function, as needed.
    function removeAllLiquidity()
        external
        payable
    {
        /******* : Implement this function *******/
        /* HINTS:
            Decide on the maximum allowable ETH that msg.sender can remove.
            Call removeLiquidity().
        */
        uint entitledETH = stakes[msg.sender].div(total_stakes).mul(eth_reserves);
        removeLiquidity(entitledETH);
    }

    /***  Define helper functions for liquidity management here as needed: ***/



    /* ========================= Swap Functions =========================  */ 

    // Function swapTokensForETH: Swaps your token with ETH
    // You can change the inputs, or the scope of your function, as needed.
    function swapTokensForETH(uint amountTokens)
        external 
        payable
    {
        /******* : Implement this function *******/
        /* HINTS:
            Calculate amount of ETH should be swapped based on exchange rate.
            Transfer the ETH to the provider.
            If the caller possesses insufficient tokens, transaction must fail.
            If performing the swap would exhaus total ETH supply, transaction must fail.
            Update token_reserves and eth_reserves.

            Part 4: 
                Expand the function to take in addition parameters as needed.
                If current exchange_rate > slippage limit, abort the swap.
            
            Part 5:
                Only exchange amountTokens * (1 - liquidity_percent), 
                    where % is sent to liquidity providers.
                Keep track of the liquidity fees to be added.
        */
        // calculate the amount of ETH
        require(token.allowance(msg.sender, address(this)) >= amountTokens, "Insuffecient tokens");
        uint equivalentETH = priceToken().mul(amountTokens);
        require(equivalentETH < eth_reserves, "Insuffecient ETH in reserves");
        // transfer funds and update state of contract
        token.transferFrom(msg.sender, address(this), amountTokens);
        eth_reserves = eth_reserves.sub(equivalentETH);
        token_reserves = token_reserves.add(amountTokens);
        payable(msg.sender).transfer(equivalentETH);
        /***************************/
        // DO NOT MODIFY BELOW THIS LINE
        /* Check for x * y == k, assuming x and y are rounded to the nearest integer. */
        // Check for Math.abs(token_reserves * eth_reserves - k) < (token_reserves + eth_reserves + 1));
        //   to account for the small decimal errors during uint division rounding.
        uint check = token_reserves.mul(eth_reserves);
        if (check >= k) {
            check = check.sub(k);
        }
        else {
            check = k.sub(check);
        }
        assert(check < (token_reserves.add(eth_reserves).add(1)));
    }



    // Function swapETHForTokens: Swaps ETH for your tokens.
    // ETH is sent to contract as msg.value.
    // You can change the inputs, or the scope of your function, as needed.
    function swapETHForTokens()
        external
        payable 
    {
        /******* TODO: Implement this function *******/
        /* HINTS:
            Calculate amount of your tokens should be swapped based on exchange rate.
            Transfer the amount of your tokens to the provider.
            If performing the swap would exhaus total token supply, transaction must fail.
            Update token_reserves and eth_reserves.

            Part 4: 
                Expand the function to take in addition parameters as needed.
                If current exchange_rate > slippage limit, abort the swap. 
            
            Part 5: 
                Only exchange amountTokens * (1 - %liquidity), 
                    where % is sent to liquidity providers.
                Keep track of the liquidity fees to be added.
        */


        /**************************/
        // DO NOT MODIFY BELOW THIS LINE
        /* Check for x * y == k, assuming x and y are rounded to the nearest integer. */
        // Check for Math.abs(token_reserves * eth_reserves - k) < (token_reserves + eth_reserves + 1));
        //   to account for the small decimal errors during uint division rounding.
        uint check = token_reserves.mul(eth_reserves);
        if (check >= k) {
            check = check.sub(k);
        }
        else {
            check = k.sub(check);
        }
        assert(check < (token_reserves.add(eth_reserves).add(1)));
    }

    /***  Define helper functions for swaps here as needed: ***/

}
