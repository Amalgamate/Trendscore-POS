import Link from 'next/link';

export default function CheckoutPage() {
  return (
    <main className="simple-page checkout-page">
      <h1>Checkout is not open yet.</h1>
      <p className="page-intro">
        This preview bag is for exploring the storefront experience. No personal
        details, order, or payment will be collected here.
      </p>

      <section className="checkout-readiness" aria-labelledby="readiness-title">
        <div className="readiness-symbol" aria-hidden="true">
          !
        </div>
        <div>
          <h2 id="readiness-title">This shop is still being connected</h2>
          <p>
            Online checkout will open after the shop connects its real catalog,
            delivery choices, and verified M-Pesa payment setup.
          </p>
        </div>
      </section>

      <ol className="checkout-steps" aria-label="What checkout will include">
        <li>
          <span>01</span>
          <div>
            <strong>Delivery or pickup</strong>
            <p>Choose an option set by the shop.</p>
          </div>
        </li>
        <li>
          <span>02</span>
          <div>
            <strong>Live stock check</strong>
            <p>Confirm availability against the POS catalog.</p>
          </div>
        </li>
        <li>
          <span>03</span>
          <div>
            <strong>Verified payment</strong>
            <p>Pay only after official M-Pesa checkout is connected.</p>
          </div>
        </li>
        <li>
          <span>04</span>
          <div>
            <strong>Order confirmation</strong>
            <p>Receive a real order reference and status updates.</p>
          </div>
        </li>
      </ol>

      <div className="checkout-actions">
        <Link className="button button-primary" href="/cart">
          Return to your preview bag
        </Link>
        <Link className="text-link" href="/">
          Back to the storefront
        </Link>
      </div>
    </main>
  );
}
