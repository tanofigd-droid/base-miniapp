// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

contract BountyQnA {
    struct Question {
        uint256 id;
        address asker;
        string text;
        string[] tags;
        uint256 bounty;
        uint256 acceptedAnswerId;
        bool isClosed;
    }

    struct Answer {
        uint256 id;
        uint256 questionId;
        address responder;
        string text;
        bool isAccepted;
    }

    IERC20 public usdc;
    address public platformWallet;
    uint256 public platformFee; // e.g., 30 = 30%
    
    uint256 public questionCount;
    uint256 public answerCount;

    mapping(uint256 => Question) public questions;
    mapping(uint256 => Answer) public answers;
    mapping(address => mapping(string => uint256)) public trustScore; // responder => tag => score

    // Events
    event QuestionPosted(uint256 indexed questionId, address indexed asker, uint256 bounty);
    event AnswerPosted(uint256 indexed answerId, uint256 indexed questionId, address indexed responder);
    event AnswerAccepted(uint256 indexed answerId, uint256 indexed questionId);

    constructor(address _usdc, address _platformWallet, uint256 _platformFee) {
        usdc = IERC20(_usdc);
        platformWallet = _platformWallet;
        platformFee = _platformFee; // 0-100
    }

    // Post a new question with USDC bounty
    function postQuestion(string memory text, string[] memory tags, uint256 bounty) external {
        require(bounty > 0, "Bounty must be > 0");
        require(usdc.transferFrom(msg.sender, address(this), bounty), "USDC transfer failed");

        questionCount++;
        questions[questionCount] = Question({
            id: questionCount,
            asker: msg.sender,
            text: text,
            tags: tags,
            bounty: bounty,
            acceptedAnswerId: 0,
            isClosed: false
        });

        emit QuestionPosted(questionCount, msg.sender, bounty);
    }

    // Post an answer to a questio
    function postAnswer(uint256 questionId, string memory text) external {
        require(questionId > 0 && questionId <= questionCount, "Invalid questionId");
        require(!questions[questionId].isClosed, "Question is closed");

        answerCount++;
        answers[answerCount] = Answer({
            id: answerCount,
            questionId: questionId,
            responder: msg.sender,
            text: text,
            isAccepted: false
        });

        emit AnswerPosted(answerCount, questionId, msg.sender);
    }

    // Accept an answer (only asker can call)
    function acceptAnswer(uint256 questionId, uint256 answerId) external {
        Question storage q = questions[questionId];
        Answer storage a = answers[answerId];

        require(msg.sender == q.asker, "Only asker can accept");
        require(!q.isClosed, "Question already closed");
        require(a.questionId == questionId, "Answer does not belong to question");

        q.acceptedAnswerId = answerId;
        q.isClosed = true;
        a.isAccepted = true;

        // Distribute bounty
        uint256 platformAmount = (q.bounty * platformFee) / 100;
        uint256 winnerAmount = q.bounty - platformAmount;

        require(usdc.transfer(a.responder, winnerAmount), "USDC transfer to winner failed");
        require(usdc.transfer(platformWallet, platformAmount), "USDC transfer to platform failed");

        // Update trust score for responder per tag
        for (uint i = 0; i < q.tags.length; i++) {
            trustScore[a.responder][q.tags[i]] += 1; // simple +1 per accepted answer
        }

        emit AnswerAccepted(answerId, questionId);
    }

    // View answers for a question
    function getAnswers(uint256 questionId) external view returns (Answer[] memory) {
        uint256 count = 0;
        for (uint256 i = 1; i <= answerCount; i++) {
            if (answers[i].questionId == questionId) count++;
        }

        Answer[] memory result = new Answer[](count);
        uint256 idx = 0;
        for (uint256 i = 1; i <= answerCount; i++) {
            if (answers[i].questionId == questionId) {
                result[idx] = answers[i];
                idx++;
            }
        }
        return result;
    }

    // View trust score for a responder and tag
    function getTrustScore(address responder, string memory tag) external view returns (uint256) {
        return trustScore[responder][tag];
    }
}
