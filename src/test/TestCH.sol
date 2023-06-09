// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./TestFactory.sol";

/// @dev    NOTE this is a testing contract and should NOT be used in prod.
/// @dev    NOTE this is a testing contract and should NOT be used in prod.
contract ClearingHouse {
    // Errors
    
    error OnlyApproved();
    error OnlyFromFactory();
    error BadEscrow();
    error InterestMinimum();
    error LTCMaximum();
    error DurationMaximum();

    // Roles

    address public operator;
    address public overseer;
    address public pendingOperator;
    address public pendingOverseer;

    // Relevant Contracts

    ERC20 public immutable dai;
    ERC20 public immutable gOHM;
    address public immutable treasury;
    CoolerFactory public immutable factory;

    // Parameter Bounds

    uint256 public constant minimumInterest = 2e16; // 2%
    uint256 public constant maxLTC = 2_500 * 1e18; // 2,500
    uint256 public constant maxDuration = 365 days; // 1 year

    constructor (
        address oper, 
        address over, 
        ERC20 g, 
        ERC20 d, 
        CoolerFactory f, 
        address t,
        uint256[] memory b
    ) {
        operator = oper;
        overseer = over;
        gOHM = g;
        dai = d;
        factory = f;
        treasury = t;
        budget = b;
    }

    // Operation

    /// @notice clear a requested loan
    /// @param cooler contract requesting loan
    /// @param id of loan in escrow contract
    /// @param time static timestamp for testing
    function clear (Cooler cooler, uint256 id, uint256 time) external returns (uint256) {
        if (msg.sender != operator) 
            revert OnlyApproved();

        // Validate escrow
        if (!factory.created(address(cooler))) 
            revert OnlyFromFactory();
        if (cooler.collateral() != gOHM || cooler.debt() != dai)
            revert BadEscrow();

        (
            uint256 amount, 
            uint256 interest, 
            uint256 ltc, 
            uint256 duration,
        ) = cooler.requests(id);

        // Validate terms
        if (interest < minimumInterest) 
            revert InterestMinimum();
        if (ltc > maxLTC) 
            revert LTCMaximum();
        if (duration > maxDuration) 
            revert DurationMaximum();

        // Clear loan
        dai.approve(address(cooler), amount);
        return cooler.clear(id, time);
    }

    /// @notice toggle 'rollable' status of a loan
    function toggleRoll(Cooler cooler, uint256 loanID) external {
        if (msg.sender != operator) 
            revert OnlyApproved();

        cooler.toggleRoll(loanID);
    }

    // Oversight

    // Funding params
    uint256[] public budget;
    uint256 public lastFunded;
    uint256 public constant cadence = 7 days;

    /// @notice pull funding using ITreasury interface
    function fund (uint256 time) external {
        if (lastFunded + cadence < time) {
            for (uint256 i; i < budget.length; i++) {
                if (budget[i] != 0) {
                    lastFunded = lastFunded == 0 ? time : lastFunded + cadence;
                    ITreasury(treasury).manage(address(dai), budget[i]);
                    delete budget[i];
                    break;
                }
            }
        }
    }

    /// @notice return funds to treasury
    /// @param token to transfer
    /// @param amount to transfer
    function defund (ERC20 token, uint256 amount) external {
        if (msg.sender != operator && msg.sender != overseer) 
            revert OnlyApproved();
        token.transfer(treasury, amount);
    }

}