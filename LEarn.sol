// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract LEarn{

    /*
     *  Events
    */
    event courseCreated(address _creatorAddress, uint256 _courseId, uint256 _courseFee);
    event TransferSent(address _from, address _destAddr, uint _amount);

    /*
     *  Storage
    */
    using Counters for Counters.Counter;
    using SafeMath for uint256;

    Counters.Counter public courseId;

    struct courseInfo{
        address creatorAddress;
        uint256 courseFee;
        uint256 numSections;
        uint256[] sectionDeadlines;
        uint256[] sectionRefundFee;
        address[] enrolledStudents;
    }

    courseInfo[] public courseDatabase;

    struct userCourseInfo{
        uint256 timeEnrolled;
        bool[] sectionsCompleted;
    }

    mapping(address => mapping(uint256 => userCourseInfo)) public userEnrolledDatabase;  

    // Constructor.
    constructor() {// 1e16 = 0.01 matic
    }

    function createCourse(uint256 _courseFee, uint256 _numSections, uint256[] memory _sectionDeadline, uint256[] memory _sectionRefundFee) external returns(uint256 _courseId){
        
        // Get the current course id to access the database and update the states.
        _courseId = courseId.current();

        // Update the database from the input parameters.
        courseInfo memory currCourse;
        courseDatabase.push(currCourse);
        courseDatabase[_courseId].creatorAddress = msg.sender;
        courseDatabase[_courseId].courseFee = _courseFee;
        courseDatabase[_courseId].numSections = _numSections;
        for(uint256 i=0; i<_numSections; i++){
            courseDatabase[_courseId].sectionDeadlines.push(_sectionDeadline[i]);
            courseDatabase[_courseId].sectionRefundFee.push(_sectionRefundFee[i]);
        }

        // Emit and event that the course has been created.
        emit courseCreated(msg.sender, _courseId, _courseFee);

        // Increment the counter as the courseId counter gives the index of the next course going to be created.
        courseId.increment();

    }

    function enrollCourse(uint256 _courseId) external payable {

        //Sanity check to prevent mutliple enrolling.
        for(uint256 i=0; i<courseDatabase[_courseId].enrolledStudents.length; i++){
            require(msg.sender != courseDatabase[_courseId].enrolledStudents[i], "Student already enrolled.");
        }

        //Sanity check incorrect course id.
        require(_courseId < courseId.current(), "Invalid course id.");
        
        //Deposit fee also and if the user doesn't have amount equal to fees revert the transaction.
        require(msg.value == courseDatabase[_courseId].courseFee, "Incorrect course fee amount");

        // Update the user course database.
        // Cases could be that user already has it's entry into the account or it might be a new user.
        userEnrolledDatabase[msg.sender][_courseId].timeEnrolled = block.timestamp;
        
        uint256 _numSections = courseDatabase[_courseId].numSections;
        for(uint256 i=0; i<_numSections; i++){
            userEnrolledDatabase[msg.sender][_courseId].sectionsCompleted.push(false);
        }

        courseDatabase[_courseId].enrolledStudents.push(msg.sender);

    }

    function calculateTimestamp(uint256 _courseId, uint256 _sectionId) public view returns(uint256){

        require(courseDatabase[_courseId].numSections > _sectionId, "Invalid Section");

        uint256 _cummTimestamp = 0;
        for(uint256 i=0; i<(_sectionId+1); i++){
            _cummTimestamp = _cummTimestamp.add(courseDatabase[_courseId].sectionDeadlines[i]);
        }

        return _cummTimestamp;
    }

    function sectionCompleted(uint256 _courseId, uint256 _sectionId) external {

        //Sanity check incorrect course id.
        require(_courseId < courseId.current(), "Invalid course id.");

        //Sanity Check that the user is enrolled also or not.
        require(userEnrolledDatabase[msg.sender][_courseId].timeEnrolled != 0, "User has not enrolled in this course");

        //Sanity check whether it has already completed the course or not and re-claiming the refund.
        require(courseDatabase[_courseId].numSections > _sectionId, "Invalid Section");
        require(userEnrolledDatabase[msg.sender][_courseId].sectionsCompleted[_sectionId] == false, "Section already completed refund isssued.");

        //Calculate the exact timestamp to refund amount.
        uint256 _cummTimestamp = calculateTimestamp(_courseId, _sectionId);
        uint256 _exactDeadline = userEnrolledDatabase[msg.sender][_courseId].timeEnrolled.add(_cummTimestamp); 

        require(block.timestamp <= _exactDeadline, "Deadline passed refund not possible.");

        //Since sanity checks passed now we can refund the amount.
        (bool success, ) = msg.sender.call{value: courseDatabase[_courseId].sectionRefundFee[_sectionId]}("");
        require(success, "Failed to send Ether");

        userEnrolledDatabase[msg.sender][_courseId].sectionsCompleted[_sectionId] = true;

    }

    function transferAmountCreator(uint256 _courseId) external {

        //Sanity check incorrect course id.
        require(_courseId < courseId.current(), "Invalid course id.");

        uint totalAmountPay = 0;

        for(uint256 i=0; i<courseDatabase[_courseId].enrolledStudents.length; i++){
            address currStudent = courseDatabase[_courseId].enrolledStudents[i];

            //Transfer course fee by calculating to the creator only after the student course deadline is met.
            uint256 _cummTimestamp = calculateTimestamp(_courseId, courseDatabase[_courseId].numSections.sub(1));
            uint256 _exactDeadline = userEnrolledDatabase[currStudent][_courseId].timeEnrolled.add(_cummTimestamp);

            if(_exactDeadline >= block.timestamp){
                continue;
            }

            totalAmountPay = totalAmountPay.add(courseDatabase[_courseId].courseFee);

            uint256 totalRefundAmount = 0;
            for(uint256 j=0; j<courseDatabase[_courseId].numSections; j++){
                if(userEnrolledDatabase[currStudent][_courseId].sectionsCompleted[j] == true){
                    totalRefundAmount = totalRefundAmount.add(courseDatabase[_courseId].sectionRefundFee[j]);
                }
            }

            totalAmountPay = totalAmountPay.sub(totalRefundAmount);
        }

        if(totalAmountPay > 0){
            (bool success, ) = courseDatabase[_courseId].creatorAddress.call{value: totalAmountPay}("");
            require(success, "Failed to send Ether");
        }
    }
}
