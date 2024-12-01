// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import './Dex/interfaces/IUBADexFactory.sol';

contract GToken is ERC20, AccessControl, ERC20Permit {

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardUBADebt;  // Reward debt in UBA
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 ubaToken;
        uint256 accUBAPerShare; // Accumulated UBA per share, times 1e12. See below.
        uint256 lastTotalUBAReward; // last total rewards in UBA 
        uint256 lastUBARewardBalance; // lastest last UBA rewards tokens that were distributed
        uint256 totalUBAReward; // total UBA rewards tokens distributed till now by admin
    }

    // Mapping to keep track of whitelisted addresses
    mapping(address => bool) public isWhitelistAddress;

    // UBA TOKEN!
    IERC20 public UBA;

    // Info of each pool.
    PoolInfo public poolInfo;
    
    // Info of each user that stakes LP tokens.
    mapping (address => UserInfo) public userInfo;

    // factory Address
    address public factory;

    // Modifier to restrict access to whitelisted addresses
    modifier onlyWhitelistAddress(address account, address to) {
        require(isWhitelistAddress[account] || isWhitelistAddress[to] || (account == address(0)), "GToken: Address is not whitelisted");
        _;
    }

    constructor(address defaultAdmin, address _UBA, address _factory, string memory name, string memory symbol)
        ERC20(name, symbol)
        ERC20Permit(symbol)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        UBA = IERC20(_UBA);
        factory = _factory;

        poolInfo = PoolInfo({
            ubaToken : UBA,
            accUBAPerShare : 0,
            lastTotalUBAReward : 0,
            lastUBARewardBalance : 0, 
            totalUBAReward : 0
        });
    }

    function mint(address to, uint256 amount) public {
        bool status = IUBADexFactory(factory).isPair(msg.sender);
        require(status, "Invalid Sender");
        _mint(to, amount);
    }

    // Function to add an address to the whitelist
    function whitelistAddress(address account, bool status) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isWhitelistAddress[account] != status, "GToken: Already in same status");
        isWhitelistAddress[account] = status;
    }

    // Function to update factory address
    function updateFactoryAddress(address _factory) public onlyRole(DEFAULT_ADMIN_ROLE) {
        factory = _factory;
    }

    // Override the _update method with the onlyWhitelistAddress modifier
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20)
        onlyWhitelistAddress(from, to)
    {
        super._update(from, to, value);

        PoolInfo storage pool = poolInfo;
        if(from == address(0)) {
            UserInfo storage user = userInfo[to];
            updatePool(to);

            //// UBA
            uint256 ubaReward = ((user.amount * pool.accUBAPerShare)/ 1e12) - user.rewardUBADebt;
            if(ubaReward > 0)
                pool.ubaToken.transfer(to, ubaReward);
            pool.lastUBARewardBalance = pool.ubaToken.balanceOf(address(this));

            user.amount = user.amount + value;
            user.rewardUBADebt = (user.amount * pool.accUBAPerShare) / 1e12;
        } else {
            UserInfo storage userFrom = userInfo[from];
            UserInfo storage userTo = userInfo[to];

            updatePool(from);
            updatePool(to);

            //// UBA
            uint256 ubaRewardFrom = ((userFrom.amount * pool.accUBAPerShare) / 1e12)- userFrom.rewardUBADebt;
            if(ubaRewardFrom > 0)
                pool.ubaToken.transfer(from, ubaRewardFrom);

            //// UBA
            uint256 ubaRewardTo = ((userTo.amount * pool.accUBAPerShare) / 1e12) - userTo.rewardUBADebt;
            if(ubaRewardTo > 0)
                pool.ubaToken.transfer(to, ubaRewardTo);
            pool.lastUBARewardBalance = pool.ubaToken.balanceOf(address(this));

            userFrom.amount = userFrom.amount - value;
            userTo.amount = userTo.amount + value;

            userFrom.rewardUBADebt = (userFrom.amount * pool.accUBAPerShare) / 1e12;
            userTo.rewardUBADebt = (userTo.amount * pool.accUBAPerShare) / 1e12;
        }
    }

    // View function to see pending UBAs on frontend.
    function pendingUBA(address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo;
        UserInfo storage user = userInfo[_user];
        uint256 accUBAPerShare = pool.accUBAPerShare;
        uint256 lpSupply = totalSupply();
        if (lpSupply != 0) {
            uint256 rewardBalance = pool.ubaToken.balanceOf(address(this));
            uint256 _totalReward = rewardBalance - pool.lastUBARewardBalance;
            accUBAPerShare = accUBAPerShare + (_totalReward * 1e12 / lpSupply);
        }
        return ((user.amount * accUBAPerShare) / 1e12) - user.rewardUBADebt;
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(address _user) internal {
        PoolInfo storage pool = poolInfo;
        UserInfo storage user = userInfo[_user];
        
        uint256 rewardBalance = pool.ubaToken.balanceOf(address(this));
        uint256 _totalReward = pool.totalUBAReward + (rewardBalance - pool.lastUBARewardBalance);
        pool.lastUBARewardBalance = rewardBalance;
        pool.totalUBAReward = _totalReward;
        
        uint256 lpSupply = totalSupply();
        if (lpSupply == 0) {
            pool.accUBAPerShare = 0;
            pool.lastTotalUBAReward = 0;
            user.rewardUBADebt = 0;
            pool.lastUBARewardBalance = 0;
            pool.totalUBAReward = 0;
            return;
        }
        
        uint256 reward = _totalReward - pool.lastTotalUBAReward;
        pool.accUBAPerShare = pool.accUBAPerShare + (reward * 1e12 / lpSupply);
        pool.lastTotalUBAReward = _totalReward;
    }

    // Earn UBA tokens to MasterChef.
    function claimUBA(address _user) public {
        PoolInfo storage pool = poolInfo;
        UserInfo storage user = userInfo[_user];
        updatePool(_user);
        
        uint256 UBAReward = ((user.amount * pool.accUBAPerShare) / 1e12) - user.rewardUBADebt;
        pool.ubaToken.transfer(_user, UBAReward);
        pool.lastUBARewardBalance = pool.ubaToken.balanceOf(address(this));
        
        user.rewardUBADebt = (user.amount * pool.accUBAPerShare)/1e12;
    }
}