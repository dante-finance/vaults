// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import "@openzeppelin/contracts/utils/Address.sol";

import "./interfaces/IMasterChef.sol";
import "./interfaces/IStrategy.sol";
import "./interfaces/IUniSwapRouter.sol";
import "./interfaces/IUniswapV2Pair.sol";

/**
    (                                                                        
    )\ )                   )        (                                        
    (()/(      )         ( /(   (    )\ )  (             )                (   
    /(_))  ( /(   (     )\()) ))\  (()/(  )\   (     ( /(   (      (    ))\  
    (_))_   )(_))  )\ ) (_))/ /((_)  /(_))((_)  )\ )  )(_))  )\ )   )\  /((_) 
    |   \ ((_)_  _(_/( | |_ (_))   (_) _| (_) _(_/( ((_)_  _(_/(  ((_)(_))   
    | |) |/ _` || ' \))|  _|/ -_)   |  _| | || ' \))/ _` || ' \))/ _| / -_)  
    |___/ \__,_||_||_|  \__|\___|   |_|   |_||_||_| \__,_||_||_| \__| \___|  

 */
contract LpAssetStrategyV2 is Ownable, Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // max num
    uint256 MAX_INT = 2**256 - 1;

    // Tokens
    address public constant wrapped = address(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);
    address public output;
    address public want;
    address public lpToken0;
    address public lpToken1;

    // Third party contracts
    address public masterchef;
    address public unirouter;
    address public wrappedToLp0Router;
    address public wrappedToLp1Router;
    address public outputToWrappedRouter;

    // Dante addresses
    address public treasury;
    address public nftStaking;
    address public strategist;
    address public sentinel;
    address public vault; 

    // Numbers
    uint256 public poolId;

    // Routes
    address[] public outputToWrappedRoute;
    address[] public wrappedToLp0Route;
    address[] public wrappedToLp1Route;
    address[] customPath;

    // Controllers
    bool public harvestOnDeposit;

    // Fee structure
    uint256 public constant FEE_DIVISOR = 1000;
    uint256 public constant PLATFORM_FEE = 40;            // 4% Platform fee
    uint256 public NFT_STAKING_FEE = 0;                   // 0% at start. Once NFTs launch fee will be set to reward NFT holders
    uint256 public TREASURY_FEE = 880;                    // 88% of Platform fees
    uint256 public CALL_FEE = 120;                        // 12% of Platform fees

    event Harvest(address indexed caller);
    event SetGrimFeeRecipient(address indexed newRecipient);
    event SetVault(address indexed newVault);
    event SetOutputToWrappedRoute(address[] indexed route, address indexed router);
    event SetWrappedToLp0Route(address[] indexed route, address indexed router);
    event SetWrappedToLp1Route(address[] indexed route, address indexed router);
    event RetireStrat(address indexed caller);
    event Panic(address indexed caller);
    event MakeCustomTxn(address indexed from, address indexed to, uint256 indexed amount);
    event SetFees(uint256 indexed totalFees);
    event SetHarvestOnDeposit(bool indexed boolean);
    event StrategistMigration(bool indexed boolean, address indexed newStrategist);

    constructor(                    // EXAMPLES    
        address _want,              // DANTE-TOMB LP
        uint256 _poolId,            // 0
        address _masterChef,        // GRAIL REWARD POOL
        address _output,            // GRAIL
        address _unirouter,         // ROUTER
        address _sentinel,          // SENTINAL
        address _dao,               // TREASURY
        address _nftStaking         // NFT STAKING 
    ) {
        strategist = msg.sender;

        want = _want;
        poolId = _poolId;
        masterchef = _masterChef;
        output = _output;
        unirouter = _unirouter;
        sentinel = _sentinel;
        treasury = _dao;
        nftStaking = _nftStaking;

        outputToWrappedRoute = [output, wrapped];
        outputToWrappedRouter = unirouter;
        wrappedToLp0Router = unirouter;
        wrappedToLp1Router = unirouter;

        lpToken0 = IUniswapV2Pair(want).token0();
        lpToken1 = IUniswapV2Pair(want).token1();

        wrappedToLp0Route = [wrapped, lpToken0];
        wrappedToLp1Route = [wrapped, lpToken1];

        harvestOnDeposit = false;
    }

    /** @dev Sets the vault connected to this strategy */
    function setVault(address _vault) external onlyOwner {
        vault = _vault;
        emit SetVault(_vault);
    }

    function setNftStaking(address _nftStaking) external onlyOwner {
        nftStaking = _nftStaking;
    }

    /** @dev Function to synchronize balances before new user deposit. Can be overridden in the strategy. */
    function beforeDeposit() external virtual {}

    /** @dev Deposits funds into the masterchef */
    function deposit() public whenNotPaused {
        require(msg.sender == vault, "!auth");
        if (balanceOfPool() == 0 || !harvestOnDeposit) {
            _deposit();
        } else {
            _deposit();
            _harvest(msg.sender);
        }
    }

    function _deposit() internal whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));
        approveTxnIfNeeded(want, masterchef, wantBal);
        IMasterChef(masterchef).deposit(poolId, wantBal);
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IMasterChef(masterchef).withdraw(poolId, _amount.sub(wantBal));
            wantBal = IERC20(want).balanceOf(address(this));             
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        IERC20(want).safeTransfer(vault, wantBal);
    }

    function harvest() external {
        require(msg.sender == tx.origin, "!auth Contract Harvest");
        _harvest(msg.sender);
    }

    /** @dev Compounds the strategy's earnings and charges fees */
    function _harvest(address caller) internal whenNotPaused {
        if (caller != vault){
            require(!Address.isContract(msg.sender), "!auth Contract Harvest");
        }

        // deposit 0 so we only get the output rewards from master chef
        IMasterChef(masterchef).deposit(poolId, 0);
        
        if (balanceOf() != 0){
            // swap output token to WFTM and get platform fees
            chargeFees(caller);

            // swap WFTM back into want LP
            addLiquidity();
        }

        // re-deposit want LP into masterchef
        _deposit();

        emit Harvest(caller);
    }

    /** @dev This function converts all funds to WFTM, charges fees, and sends fees to respective accounts */
    function chargeFees(address caller) internal {                   
        uint256 toWrapped = IERC20(output).balanceOf(address(this));

        approveTxnIfNeeded(output, outputToWrappedRouter, toWrapped);

        // swapping output token for WFTM
        IUniSwapRouter(outputToWrappedRouter).swapExactTokensForTokens(toWrapped, 0, outputToWrappedRoute, address(this), block.timestamp);                                                

        uint256 wrappedBal = IERC20(wrapped).balanceOf(address(this)).mul(PLATFORM_FEE).div(FEE_DIVISOR);          
                                                
        uint256 callFeeAmount = wrappedBal.mul(CALL_FEE).div(FEE_DIVISOR);        
        IERC20(wrapped).safeTransfer(caller, callFeeAmount);
                                                      
        uint256 treasuryAmount = wrappedBal.mul(TREASURY_FEE).div(FEE_DIVISOR);        
        IERC20(wrapped).safeTransfer(treasury, treasuryAmount);

        if(NFT_STAKING_FEE > 0) {
            uint256 nftStakingAmount = wrappedBal.mul(NFT_STAKING_FEE).div(FEE_DIVISOR);        
            IERC20(wrapped).safeTransfer(nftStaking, nftStakingAmount);
        }
    }

    /** @dev Converts WFTM to both sides of the LP token and builds the liquidity pair */
    function addLiquidity() internal {
        uint256 wrappedHalf = IERC20(wrapped).balanceOf(address(this)).div(2);

        approveTxnIfNeeded(wrapped, wrappedToLp0Router, wrappedHalf);
        approveTxnIfNeeded(wrapped, wrappedToLp1Router, wrappedHalf);

        if (lpToken0 != wrapped) {
            IUniSwapRouter(wrappedToLp0Router).swapExactTokensForTokens(wrappedHalf, 0, wrappedToLp0Route, address(this), block.timestamp);
        }
        if (lpToken1 != wrapped) {
            IUniSwapRouter(wrappedToLp1Router).swapExactTokensForTokens(wrappedHalf, 0, wrappedToLp1Route, address(this), block.timestamp);
        }

        uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));

        approveTxnIfNeeded(lpToken0, unirouter, lp0Bal);
        approveTxnIfNeeded(lpToken1, unirouter, lp1Bal);

        IUniSwapRouter(unirouter).addLiquidity(lpToken0, lpToken1, lp0Bal, lp1Bal, 1, 1, address(this), block.timestamp);
    }

    /** @dev Determines the amount of reward in WFTM upon calling the harvest function */
    function callReward() public view returns (uint256) {
        uint256 outputBal = IMasterChef(masterchef).pendingShare(poolId, address(this));
        uint256 nativeOut;

        if (outputBal > 0) {
            uint256[] memory amountsOut = IUniSwapRouter(unirouter).getAmountsOut(outputBal, outputToWrappedRoute);
            nativeOut = amountsOut[amountsOut.length -1];
        }

        return nativeOut.mul(PLATFORM_FEE).div(FEE_DIVISOR).mul(CALL_FEE).div(FEE_DIVISOR);
    }

    /** @dev calculate the total underlaying 'want' held by the strat */
    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceOfPool());
    }

    /** @dev it calculates how much 'want' this contract holds */
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    /** @dev it calculates how much 'want' the strategy has working in the farm */
    function balanceOfPool() public view returns (uint256) {
        (uint256 _amount, ) = IMasterChef(masterchef).userInfo(poolId, address(this));
        return _amount;
    }

    /** @dev called as part of strat migration. Sends all the available funds back to the vault */
    function retireStrat() external {
        require(msg.sender == vault, "!vault");
        IMasterChef(masterchef).emergencyWithdraw(poolId);
        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);

        emit RetireStrat(msg.sender);
    }

    /** @dev Pauses the strategy contract and executes the emergency withdraw function */
    function panic() public {
        require(msg.sender == sentinel, "!auth");
        pause();
        IMasterChef(masterchef).emergencyWithdraw(poolId);

        emit Panic(msg.sender);
    }

    /** @dev Pauses the strategy contract */
    function pause() public {
        require(msg.sender == sentinel, "!auth");
        _pause();
        _removeAllowances();
    }

    /** @dev Unpauses the strategy contract */
    function unpause() external {
        require(msg.sender == sentinel, "!auth");
        _unpause();
        _deposit();
    }

    /** @dev Removes allowances to spenders */
    function _removeAllowances() internal {
        IERC20(want).safeApprove(masterchef, 0);
        IERC20(output).safeApprove(outputToWrappedRouter, 0);
        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, 0);
    }

    /** @dev This function exists incase tokens that do not match the {want} of this strategy accrue.  For example: an amount of
    tokens sent to this address in the form of an airdrop of a different token type.  This will allow Grim to convert
    said token to the {want} token of the strategy, allowing the amount to be paid out to stakers in the matching vault. */ 
    function makeCustomTxn(address[] calldata _path, uint256 _amount) external onlyOwner {
        require (_path[0] != output && _path[_path.length - 1] == output, "Bad path || !auth");

        approveTxnIfNeeded(_path[0], unirouter, _amount);

        IUniSwapRouter(unirouter).swapExactTokensForTokens(_amount, 0, _path, address(this), block.timestamp.add(600));
   
        emit MakeCustomTxn(_path[0], _path[_path.length - 1], _amount);
    }

    /** @dev Modular function to set the output to wrapped route */
    function setOutputToWrappedRoute(address[] calldata _route, address _router) external onlyOwner {
        require(_route[0] == output && _route[_route.length - 1] == wrapped, "Bad path || !auth");

        outputToWrappedRoute = _route;
        outputToWrappedRouter = _router;

        emit SetOutputToWrappedRoute(_route, _router);
    }

    /** @dev Modular function to set the transaction route of LP token 0 */
    function setWrappedToLp0Route(address[] calldata _route, address _router) external onlyOwner {
        require (_route[0] == wrapped && _route[_route.length - 1] == lpToken0, "Bad path || !auth");

        wrappedToLp0Route = _route;
        wrappedToLp0Router = _router;

        emit SetWrappedToLp0Route(_route, _router);
    }

    /** @dev Modular function to set the transaction route of LP token 1 */
    function setWrappedToLp1Route(address[] calldata _route, address _router) external onlyOwner {
        require (_route[0] == wrapped && _route[_route.length - 1] == lpToken1, "Bad path || !auth");

        wrappedToLp1Route = _route;
        wrappedToLp1Router = _router;

        emit SetWrappedToLp1Route(_route, _router);
    }

    /** @dev Internal function to approve the transaction if the allowance is below transaction amount */
    function approveTxnIfNeeded(address _token, address _spender, uint256 _amount) internal {
        uint256 allowance = IERC20(_token).allowance(address(this), _spender);
        
        if (allowance < _amount) {
            uint256 increase = MAX_INT - allowance;
            IERC20(_token).safeIncreaseAllowance(_spender, increase);
        }
    }

    /** @dev Sets the fee amounts */
    function setFees(
        uint256 newCallFee,
        uint256 newTreasuryFee,
        uint256 newNftStakingFee) external onlyOwner {

        uint256 sum = newCallFee.add(newTreasuryFee).add(newNftStakingFee);
        require(sum <= FEE_DIVISOR, "Exceeds max");

        CALL_FEE = newCallFee;
        NFT_STAKING_FEE = newNftStakingFee;
        TREASURY_FEE = newTreasuryFee;

        emit SetFees(sum);
    }
}