const { Socket } = Phoenix;
const { LiveSocket } = LiveView;

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
const liveSocket = new LiveSocket("/live", Socket, { params: { _csrf_token: csrfToken } });

liveSocket.connect();

// Expose for debugging in browser console
window.liveSocket = liveSocket;

// Handle flash close
document.querySelectorAll("[role=alert][data-flash]").forEach((el) => {
  el.addEventListener("click", () => {
    el.setAttribute("hidden", "");
  });
});
