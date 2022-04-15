// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IDanteStrategy.sol";

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
contract SentinelV2 is Ownable {

    // Events
    event AddNewStrategy(address indexed newStrategy);
    event RemoveStrategy(address indexed removedStrategy);
    event SetOwner(address indexed newOwner);
    event PauseAll(address caller);
    event UnpauseAll(address caller);
    event PauseError(address strategy);
    event UnpauseError(address strategy);

    // Dante addresses
    address[] strategy;

    constructor () {}

    ////////////
    // Public //
    ////////////

    function reportStrategyLength() public view returns (uint256) {
        return strategy.length;
    }

    function strategyIndex(uint256 index) public view returns (address) {
        return strategy[index];
    }
        
    function findStrategyIndex(address _strategy) public view returns (uint256, bool) {
        uint256 index;
        bool found = false;

        for (uint256 i = 0; i < strategy.length; i++) {
            if (strategy[i] == _strategy) {
                index = i;
                found = true;
            }
        }

        return (index, found);
    }

    ////////////////
    // Restricted //
    ////////////////

    function removeStrategyFromIndex(address _strategyToRemove) external onlyOwner {
        address tempAddress;
        address swapAddress;

        for (uint256 i = 0; i < strategy.length; i++) {
            if (strategy[i] == _strategyToRemove) {
                tempAddress = _strategyToRemove;
                swapAddress = strategy[strategy.length - 1];
                strategy[i] = swapAddress;
                strategy[strategy.length - 1] = tempAddress;

                strategy.pop();
                emit RemoveStrategy(tempAddress);
            }
        }

    }

    function addNewStrategy(address _strat) external onlyOwner {
        bool found = false;
        ( , found) = findStrategyIndex(_strat);
        
        if (!found) {
            strategy.push(_strat);
        }

        emit AddNewStrategy(_strat);
    }

    function pauseAll(uint256 start, uint256 end) external onlyOwner {

        for(uint256 i = start; i < end + 1; i++) {

            try DanteStrategy(strategy[i]).pause()
            {} catch {
                emit PauseError(strategy[i]);
            }
        }
    }

    function unpauseAll(uint256 start, uint256 end) external onlyOwner {
        
        for(uint256 i = start; i < end + 1; i++) {

            try DanteStrategy(strategy[i]).unpause()
            {} catch {
                emit UnpauseError(strategy[i]);
            }
        }
    }
}