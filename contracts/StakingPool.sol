// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Interfaces/IBERA20.sol";

// StakingPool is the master of Uba. He can make Uba and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once UBA is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract StakingPool is Ownable {

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of UBAs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accUbaPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accUbaPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBERA20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. UBAs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that UBAs distribution occurs.
        uint256 accUbaPerShare;   // Accumulated UBAs per share, times 1e12. See below.
        uint16 depositFeeBP;      // Deposit fee in basis points
    }

    // The UBA TOKEN!
    IBERA20 public uba;
    // Dev address.
    address public devaddr;
    // UBA tokens created per block.
    uint256 public ubaPerBlock;
    // Bonus muliplier for early uba makers.
    uint256 public constant BONUS_MULTIPLIER = 1;
    // Deposit Fee address
    address public feeAddress;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when UBA mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        address initialOwner,
        IBERA20 _uba,
        address _devaddr,
        address _feeAddress,
        uint256 _ubaPerBlock,
        uint256 _startBlock
    ) Ownable(initialOwner) {
        uba = _uba;
        devaddr = _devaddr;
        feeAddress = _feeAddress;
        ubaPerBlock = _ubaPerBlock;
        startBlock = _startBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IBERA20 _lpToken, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner {
        require(_depositFeeBP <= 10000, "add: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint + _allocPoint;
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accUbaPerShare: 0,
            depositFeeBP: _depositFeeBP
        }));
    }

    // Update the given pool's UBA allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner {
        require(_depositFeeBP <= 10000, "set: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = (totalAllocPoint - poolInfo[_pid].allocPoint) + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return ((_to - _from) * BONUS_MULTIPLIER);
    }

    // View function to see pending UBAs on frontend.
    function pendingUba(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accUbaPerShare = pool.accUbaPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 ubaReward = ((multiplier * ubaPerBlock) * pool.allocPoint) / totalAllocPoint;
            accUbaPerShare = accUbaPerShare + ((ubaReward * 1e12) / lpSupply);
        }
        return ((user.amount * accUbaPerShare) / 1e12) - user.rewardDebt;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 ubaReward = ((multiplier * ubaPerBlock) * pool.allocPoint) / totalAllocPoint;
        IBERA20(uba).mint(devaddr, ubaReward / 10);
        IBERA20(uba).mint(address(this), ubaReward);
        pool.accUbaPerShare = pool.accUbaPerShare + ((ubaReward * 1e12) / lpSupply);
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to StakingPool for UBA allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = ((user.amount * pool.accUbaPerShare) / 1e12) - user.rewardDebt;
            if(pending > 0) {
                safeUbaTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.transferFrom(address(msg.sender), address(this), _amount);
            if(pool.depositFeeBP > 0){
                uint256 depositFee = ((_amount * pool.depositFeeBP) / 10000);
                pool.lpToken.transfer(feeAddress, depositFee);
                user.amount = (user.amount + _amount) - depositFee;
            }else{
                user.amount = user.amount + _amount;
            }
        }
        user.rewardDebt = ((user.amount * pool.accUbaPerShare) / 1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from StakingPool.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = ((user.amount * pool.accUbaPerShare) / 1e12) - user.rewardDebt;
        if(pending > 0) {
            safeUbaTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount - _amount;
            pool.lpToken.transfer(address(msg.sender), _amount);
        }
        user.rewardDebt = ((user.amount * pool.accUbaPerShare) / 1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.transfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe uba transfer function, just in case if rounding error causes pool to not have enough UBAs.
    function safeUbaTransfer(address _to, uint256 _amount) internal {
        uint256 ubaBal = IBERA20(uba).balanceOf(address(this));
        if (_amount > ubaBal) {
            IBERA20(uba).transfer(_to, ubaBal);
        } else {
            IBERA20(uba).transfer(_to, _amount);
        }
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }

    function setFeeAddress(address _feeAddress) public{
        require(msg.sender == feeAddress, "setFeeAddress: FORBIDDEN");
        feeAddress = _feeAddress;
    }

    //Pancake has to add hidden dummy pools inorder to alter the emission, here we make it simple and transparent to all.
    function updateEmissionRate(uint256 _ubaPerBlock) public onlyOwner {
        massUpdatePools();
        ubaPerBlock = _ubaPerBlock;
    }
}