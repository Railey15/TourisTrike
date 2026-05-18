import React from "react";

function formatTime(date) {
  return date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

// Simple SVG icons — no icon library dependency required
const BotIcon = () => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
    <path d="M7 11V7a5 5 0 0 1 10 0v4" />
    <line x1="12" y1="3" x2="12" y2="7" />
    <circle cx="9" cy="16" r="1" fill="currentColor" stroke="none" />
    <circle cx="15" cy="16" r="1" fill="currentColor" stroke="none" />
  </svg>
);

export default function MessageBubble({ message }) {
  const isUser = message.role === "user";

  return (
    <div className={`message-row ${isUser ? "user" : "ai"}`}>
      {!isUser && (
        <div className="message-avatar">
          <BotIcon />
        </div>
      )}

      <div className="message-bubble-wrap">
        <div className="message-bubble">{message.content}</div>
        <span className="message-time">{formatTime(message.timestamp)}</span>
      </div>
    </div>
  );
}
