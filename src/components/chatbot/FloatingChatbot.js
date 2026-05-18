import React, { useState, useEffect } from "react";
import ChatWindow from "./ChatWindow";
import "./chatbot.css";

const ChatIcon = () => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
    <line x1="9" y1="10" x2="15" y2="10" />
    <line x1="12" y1="7" x2="12" y2="13" />
  </svg>
);

const CloseIcon = () => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
    <line x1="18" y1="6" x2="6" y2="18" />
    <line x1="6" y1="6" x2="18" y2="18" />
  </svg>
);

/**
 * FloatingChatbot
 *
 * Drop this anywhere inside the tourist layout — it renders a fixed
 * floating button + slide-up chat window. No portal/provider needed.
 *
 * Usage:
 *   import FloatingChatbot from "../components/chatbot/FloatingChatbot";
 *   // Inside your tourist page/layout JSX:
 *   <FloatingChatbot />
 */
export default function FloatingChatbot() {
  const [isOpen, setIsOpen] = useState(false);
  const [showBadge, setShowBadge] = useState(true);

  // Hide the notification badge once the user opens the chat
  useEffect(() => {
    if (isOpen) setShowBadge(false);
  }, [isOpen]);

  // Close chat on Escape key
  useEffect(() => {
    function handleKey(e) {
      if (e.key === "Escape" && isOpen) setIsOpen(false);
    }
    window.addEventListener("keydown", handleKey);
    return () => window.removeEventListener("keydown", handleKey);
  }, [isOpen]);

  return (
    <>
      {/* Chat window — rendered always, visibility controlled via CSS class */}
      <ChatWindow isOpen={isOpen} onClose={() => setIsOpen(false)} />

      {/* Floating toggle button */}
      <button
        className="chatbot-toggle"
        onClick={() => setIsOpen((prev) => !prev)}
        aria-label={isOpen ? "Close tourism assistant" : "Open tourism assistant"}
        title="Tourism Assistant"
      >
        {showBadge && !isOpen && <span className="chatbot-badge">1</span>}
        {isOpen ? <CloseIcon /> : <ChatIcon />}
      </button>
    </>
  );
}
