import React, { useState, useRef, useEffect } from "react";
import MessageBubble from "./MessageBubble";
import ChatInput from "./ChatInput";

const BACKEND_URL = "http://localhost:5000/chat";

const WELCOME_MESSAGE = {
  role: "ai",
  content: "Hello! 👋 I'm your Tourism Assistant. I can help you with:\n\n• Tourist spots & destinations\n• Travel packages & itineraries\n• Transportation & routes\n• Café hopping recommendations\n• Municipality information\n\nHow can I help you today?",
  timestamp: new Date(),
};

const SUGGESTIONS = [
  "🗺️ Tourist spots near me",
  "🚌 Transportation options",
  "📦 Travel packages",
  "☕ Café hopping spots",
];

const BotIcon = () => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
    <path d="M7 11V7a5 5 0 0 1 10 0v4" />
    <line x1="12" y1="3" x2="12" y2="7" />
    <circle cx="9" cy="16" r="1" fill="currentColor" stroke="none" />
    <circle cx="15" cy="16" r="1" fill="currentColor" stroke="none" />
  </svg>
);

const CloseIcon = () => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
    <line x1="18" y1="6" x2="6" y2="18" />
    <line x1="6" y1="6" x2="18" y2="18" />
  </svg>
);

export default function ChatWindow({ isOpen, onClose }) {
  const [messages, setMessages] = useState([WELCOME_MESSAGE]);
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);
  const [showSuggestions, setShowSuggestions] = useState(true);
  const messagesEndRef = useRef(null);

  // Auto-scroll to bottom whenever messages change or loading state changes
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, loading]);

  async function sendMessage(text) {
    const content = (text ?? input).trim();
    if (!content || loading) return;

    setInput("");
    setShowSuggestions(false);

    const userMsg = { role: "user", content, timestamp: new Date() };
    const updatedMessages = [...messages, userMsg];
    setMessages(updatedMessages);
    setLoading(true);

    // Build the history payload for the API (exclude the first welcome message)
    const history = updatedMessages
      .filter((m) => m.role === "user" || (m.role === "ai" && m !== WELCOME_MESSAGE))
      .map((m) => ({ role: m.role === "ai" ? "assistant" : "user", content: m.content }));

    try {
      const res = await fetch(BACKEND_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ messages: history }),
      });

      if (!res.ok) throw new Error(`Server error: ${res.status}`);

      const data = await res.json();
      const aiMsg = {
        role: "ai",
        content: data.reply ?? "Sorry, I couldn't get a response. Please try again.",
        timestamp: new Date(),
      };
      setMessages((prev) => [...prev, aiMsg]);
    } catch (err) {
      setMessages((prev) => [
        ...prev,
        {
          role: "ai",
          content: "⚠️ I'm having trouble connecting right now. Please check your connection and try again.",
          timestamp: new Date(),
        },
      ]);
    } finally {
      setLoading(false);
    }
  }

  function handleSuggestion(chip) {
    sendMessage(chip.replace(/^[\p{Emoji}\s]+/u, "").trim() || chip);
  }

  return (
    <div className={`chat-window ${isOpen ? "open" : ""}`} role="dialog" aria-label="Tourism Assistant">
      {/* Header */}
      <div className="chat-header">
        <div className="chat-header-avatar">
          <BotIcon />
        </div>
        <div className="chat-header-info">
          <p className="chat-header-name">Tourism Assistant</p>
          <p className="chat-header-status">Always here to help</p>
        </div>
        <button className="chat-header-close" onClick={onClose} aria-label="Close chat">
          <CloseIcon />
        </button>
      </div>

      {/* Messages */}
      <div className="chat-messages">
        <div className="chat-date-divider">Today</div>

        {messages.map((msg, i) => (
          <MessageBubble key={i} message={msg} />
        ))}

        {loading && (
          <div className="typing-indicator">
            <div className="message-avatar">
              <BotIcon />
            </div>
            <div className="typing-dots">
              <div className="typing-dot" />
              <div className="typing-dot" />
              <div className="typing-dot" />
            </div>
          </div>
        )}

        <div ref={messagesEndRef} />
      </div>

      {/* Quick suggestion chips — shown until first user message */}
      {showSuggestions && (
        <div className="chat-suggestions">
          {SUGGESTIONS.map((chip) => (
            <button
              key={chip}
              className="suggestion-chip"
              onClick={() => handleSuggestion(chip)}
              disabled={loading}
            >
              {chip}
            </button>
          ))}
        </div>
      )}

      {/* Input */}
      <ChatInput
        value={input}
        onChange={setInput}
        onSend={() => sendMessage()}
        disabled={loading}
      />

      {/* Footer */}
      <div className="chat-footer">Powered by TourisTrike AI</div>
    </div>
  );
}
