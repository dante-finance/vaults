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

const { ethers } = require("hardhat");

async function main() {

    const __want =          "0xac32e07c25cb18266841ed7035390744cd3b1155";
    const __poolId =        "0";
    const __masterChef =    "0xb2922e886ab9dff160479431f831a43c983a9ef3";
    const __output =        "0x255861b569d44df3e113b6ca090a1122046e6f89";
    const __unirouter =     "0xf491e7b69e4244ad4002bc14e878a34207e38c29";
    const __dao =           "0x698d286d660B298511E49dA24799d16C74b5640D";
    const __nftStaking =    "0x0000000000000000000000000000000000000000";

    const __name =          "d-R-DAN-TOM";
    const __symbol =        "d-R-DAN-TOM";

    // deploy sentinal
    const SentinelV2 = await ethers.getContractFactory("SentinelV2");
    const sentinal = await SentinelV2.deploy();

    // deploy strategy
    const LpAssetStrategyV2 = await ethers.getContractFactory("LpAssetStrategyV2");

    /*
        address _want,              // DANTE-TOMB LP
        uint256 _poolId,            // 0
        address _masterChef,        // GRAIL REWARD POOL
        address _output,            // GRAIL
        address _unirouter,         // ROUTER
        address _sentinel,          // SENTINAL
        address _dao,               // TREASURY
        address _nftStaking         // NFT STAKING 
    */
    const strategy = await LpAssetStrategyV2.deploy(__want,__poolId,__masterChef,__output,__unirouter,sentinal.address,__dao,__nftStaking);

    // deploy vault
    const DanteVault = await ethers.getContractFactory("DanteVault");

    /* 
        IStrategy _strategy,
        string memory _name,
        string memory _symbol
    */
    const vault = await DanteVault.deploy(strategy.address,__name,__symbol);

    await strategy.setVault(vault.address);

    // router WFTM => TOMB => DANTE
    await strategy.setWrappedToLp1Route(["0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83","0x6c021Ae822BEa943b2E66552bDe1D2696a53fbB7","0xDA763530614fb51DFf9673232C8B3b3e0A67bcf2"],__unirouter);

    console.log("done.");
}
    
main()
.then(() => process.exit(0))
.catch((error) => {
    console.error(error);
    process.exit(1);
});