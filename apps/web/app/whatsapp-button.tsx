const phone = (process.env.NEXT_PUBLIC_STORE_WHATSAPP_NUMBER ?? '').replace(
  /\D/g,
  '',
);
const whatsappHref =
  phone.length >= 10 && phone.length <= 15
    ? `https://wa.me/${phone}`
    : undefined;

export function WhatsAppButton() {
  if (!whatsappHref) {
    return null;
  }

  return (
    <a
      className="whatsapp-button"
      href={whatsappHref}
      target="_blank"
      rel="noopener noreferrer"
      aria-label="Chat with this shop on WhatsApp"
    >
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <path
          d="M20.5 11.8a8.4 8.4 0 0 1-12.4 7.4L4 20l.9-4A8.4 8.4 0 1 1 20.5 11.8Z"
          fill="none"
          stroke="currentColor"
          strokeWidth="1.8"
          strokeLinejoin="round"
        />
        <path
          d="M8.5 8.4c.3-.6.6-.6 1-.6h.4c.2 0 .4 0 .5.4l.7 1.7c.1.2.1.4-.1.6l-.5.6c-.2.2-.2.4 0 .6.5.9 1.2 1.5 2.1 2 .2.1.4.1.6-.1l.6-.7c.2-.2.4-.2.6-.1l1.6.8c.3.1.4.3.4.5 0 .4-.2 1.2-.7 1.5-.4.4-1 .6-1.7.5-1-.1-2.3-.7-3.7-2-1.2-1.1-2-2.5-2.2-3.4-.2-.8.1-1.6.4-2.1Z"
          fill="currentColor"
        />
      </svg>
      WhatsApp us
    </a>
  );
}
