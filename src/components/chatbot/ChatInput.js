import React, { useRef, useEffect } from "react";

const SendIcon = () => (
  <svg viewBox="0 0 24 24" fill="currentColor">
    <path d="M2.01 21L23 12 2.01 3 2 10l15 2-15 2z" />
  </svg>
);

export default function ChatInput({ value, onChange, onSend, disabled }) {
  const textareaRef = useRef(null);

  // Auto-resize the textarea as the user types
  useEffect(() => {
    const ta = textareaRef.current;
    if (!ta) return;
    ta.style.height = "auto";
    ta.style.height = `${Math.min(ta.scrollHeight, 100)}px`;
  }, [value]);

  function handleKeyDown(e) {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      if (!disabled && value.trim()) onSend();
    }
  }

  return (
    <div className="chat-input-area">
      <textarea
        ref={textareaRef}
        className="chat-input-field"
        placeholder="Ask about places, routes, packages…"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        onKeyDown={handleKeyDown}
        disabled={disabled}
        rows={1}
      />
      <button
        className="chat-send-btn"
        onClick={onSend}
        disabled={disabled || !value.trim()}
        aria-label="Send message"
      >
        <SendIcon />
      </button>
    </div>
  );
}
