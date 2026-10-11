'use client';

import Link from 'next/link';
import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { formatStorePrice } from '../store-data';
import { useStoreCart } from '../store-cart';

type FulfillmentMethod = 'DELIVERY' | 'PICKUP';

type StorefrontOrder = {
  id: string;
  orderNumber: string;
  status: 'AWAITING_PAYMENT' | 'CANCELLED' | 'EXPIRED';
  fulfillmentMethod: FulfillmentMethod;
  subtotal: number;
  deliveryFee: number | null;
  deliveryFeeQuotedAt: string | null;
  deliveryFeeAcceptedAt: string | null;
  total: number;
  expiresAt: string;
  createdAt: string;
  items: Array<{
    productName: string;
    variantLabel: string | null;
    quantity: number;
    unitPrice: number;
    lineTotal: number;
  }>;
  statusEvents: Array<{
    toStatus: string;
    detail: string;
    createdAt: string;
  }>;
};

type SavedOrder = { accessKey: string; order: StorefrontOrder };

const checkoutKeyStorage = 'shopsmart-storefront-checkout-key';
const savedOrderStorage = 'shopsmart-storefront-last-order';

function apiBaseUrl() {
  return (process.env.NEXT_PUBLIC_SHOP_API_BASE_URL ?? '/api').replace(/\/+$/, '');
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isOrderStatus(value: unknown): value is StorefrontOrder['status'] {
  return value === 'AWAITING_PAYMENT' || value === 'CANCELLED' || value === 'EXPIRED';
}

function parseStorefrontOrder(value: unknown): StorefrontOrder {
  if (!isRecord(value)) {
    throw new Error('The shop returned an invalid order response.');
  }
  const data = value;
  if (
    typeof data.id !== 'string' ||
    typeof data.orderNumber !== 'string' ||
    !isOrderStatus(data.status) ||
    (data.fulfillmentMethod !== 'DELIVERY' && data.fulfillmentMethod !== 'PICKUP') ||
    typeof data.subtotal !== 'number' ||
    !Number.isFinite(data.subtotal) ||
    (data.deliveryFee !== undefined &&
      data.deliveryFee !== null &&
      (typeof data.deliveryFee !== 'number' ||
        !Number.isFinite(data.deliveryFee) ||
        data.deliveryFee < 0)) ||
    (data.deliveryFeeQuotedAt !== undefined &&
      data.deliveryFeeQuotedAt !== null &&
      (typeof data.deliveryFeeQuotedAt !== 'string' ||
        Number.isNaN(Date.parse(data.deliveryFeeQuotedAt)))) ||
    (data.deliveryFeeAcceptedAt !== undefined &&
      data.deliveryFeeAcceptedAt !== null &&
      (typeof data.deliveryFeeAcceptedAt !== 'string' ||
        Number.isNaN(Date.parse(data.deliveryFeeAcceptedAt)))) ||
    typeof data.total !== 'number' ||
    !Number.isFinite(data.total) ||
    typeof data.expiresAt !== 'string' ||
    Number.isNaN(Date.parse(data.expiresAt)) ||
    typeof data.createdAt !== 'string' ||
    Number.isNaN(Date.parse(data.createdAt)) ||
    !Array.isArray(data.items) ||
    !data.items.every(
      (item) =>
        isRecord(item) &&
        typeof item.productName === 'string' &&
        (typeof item.variantLabel === 'string' || item.variantLabel === null) &&
        typeof item.quantity === 'number' &&
        Number.isFinite(item.quantity) &&
        item.quantity > 0 &&
        typeof item.unitPrice === 'number' &&
        Number.isFinite(item.unitPrice) &&
        typeof item.lineTotal === 'number' &&
        Number.isFinite(item.lineTotal),
    ) ||
    !Array.isArray(data.statusEvents) ||
    !data.statusEvents.every(
      (event) =>
        isRecord(event) &&
        typeof event.toStatus === 'string' &&
        typeof event.detail === 'string' &&
        typeof event.createdAt === 'string' &&
        !Number.isNaN(Date.parse(event.createdAt)),
    )
  ) {
    throw new Error('The shop returned an invalid order response.');
  }
  return {
    id: data.id,
    orderNumber: data.orderNumber,
    status: data.status,
    fulfillmentMethod: data.fulfillmentMethod,
    subtotal: data.subtotal,
    deliveryFee: typeof data.deliveryFee === 'number' ? data.deliveryFee : null,
    deliveryFeeQuotedAt:
      typeof data.deliveryFeeQuotedAt === 'string'
        ? data.deliveryFeeQuotedAt
        : null,
    deliveryFeeAcceptedAt:
      typeof data.deliveryFeeAcceptedAt === 'string'
        ? data.deliveryFeeAcceptedAt
        : null,
    total: data.total,
    expiresAt: data.expiresAt,
    createdAt: data.createdAt,
    items: data.items.map((item) => ({
      productName: String(item.productName),
      variantLabel: typeof item.variantLabel === 'string' ? item.variantLabel : null,
      quantity: Number(item.quantity),
      unitPrice: Number(item.unitPrice),
      lineTotal: Number(item.lineTotal),
    })),
    statusEvents: data.statusEvents.map((event) => ({
      toStatus: String(event.toStatus),
      detail: String(event.detail),
      createdAt: String(event.createdAt),
    })),
  };
}

async function readOrderResponse(response: Response): Promise<StorefrontOrder> {
  const payload: unknown = await response.json();
  if (!isRecord(payload)) {
    throw new Error('The shop returned an invalid order response.');
  }
  return parseStorefrontOrder(payload.data);
}

async function responseMessage(response: Response) {
  try {
    const payload: unknown = await response.json();
    if (
      typeof payload === 'object' &&
      payload !== null &&
      'error' in payload &&
      typeof payload.error === 'object' &&
      payload.error !== null &&
      'message' in payload.error &&
      typeof payload.error.message === 'string'
    ) {
      return payload.error.message;
    }
  } catch {
    // Use the status-based message if the server did not return JSON.
  }
  return `The shop could not process this request (HTTP ${response.status}).`;
}

function expiryLabel(value: string) {
  const date = new Date(value);
  return Number.isNaN(date.valueOf())
    ? 'in 15 minutes'
    : date.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
}

export default function CheckoutPage() {
  const {
    products,
    catalogState,
    storefrontProfile,
    storefrontProfileLoaded,
    items,
    subtotal,
    hydrated,
    clear,
  } = useStoreCart();
  const [customerName, setCustomerName] = useState('');
  const [customerPhone, setCustomerPhone] = useState('');
  const [customerEmail, setCustomerEmail] = useState('');
  const [fulfillmentMethod, setFulfillmentMethod] = useState<FulfillmentMethod>('DELIVERY');
  const [deliveryAddress, setDeliveryAddress] = useState('');
  const [privacyAccepted, setPrivacyAccepted] = useState(false);
  const [checkoutKey, setCheckoutKey] = useState('');
  const [orderAccessKey, setOrderAccessKey] = useState('');
  const [order, setOrder] = useState<StorefrontOrder | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [refreshingOrder, setRefreshingOrder] = useState(false);
  const [cancelling, setCancelling] = useState(false);
  const [acceptingFee, setAcceptingFee] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const restoreAttempted = useRef(false);

  const cartLines = useMemo(
    () =>
      items.flatMap((line) => {
        const product = products.find((entry) => entry.id === line.productId);
        return product ? [{ ...line, product }] : [];
      }),
    [items, products],
  );
  const deliveryAvailable = storefrontProfile.deliveryEnabled;
  const pickupAvailable = storefrontProfile.pickupEnabled;
  const fulfillmentAvailable = deliveryAvailable || pickupAvailable;
  const bagCanBeOrdered =
    cartLines.length > 0 &&
    cartLines.length === items.length &&
    cartLines.every(({ product }) => product.available);

  useEffect(() => {
    try {
      const savedKey = sessionStorage.getItem(checkoutKeyStorage);
      const key = savedKey ?? crypto.randomUUID();
      sessionStorage.setItem(checkoutKeyStorage, key);
      setCheckoutKey(key);
    } catch (storageError) {
      console.error('Could not prepare a safe checkout retry key.', storageError);
      setError('This browser could not start secure checkout. Please enable session storage and try again.');
    }
  }, []);

  useEffect(() => {
    if (!storefrontProfileLoaded) return;
    setFulfillmentMethod(deliveryAvailable ? 'DELIVERY' : 'PICKUP');
  }, [deliveryAvailable, pickupAvailable, storefrontProfileLoaded]);

  const rememberOrder = useCallback((accessKey: string, nextOrder: StorefrontOrder) => {
    restoreAttempted.current = true;
    setOrderAccessKey(accessKey);
    setOrder(nextOrder);
    try {
      sessionStorage.setItem(
        savedOrderStorage,
        JSON.stringify({ accessKey, order: nextOrder } satisfies SavedOrder),
      );
    } catch (storageError) {
      console.error('Could not retain the order confirmation in this session.', storageError);
    }
  }, []);

  useEffect(() => {
    if (
      restoreAttempted.current ||
      !checkoutKey ||
      !hydrated ||
      items.length > 0
    ) {
      return;
    }
    restoreAttempted.current = true;
    try {
      const raw = sessionStorage.getItem(savedOrderStorage);
      if (!raw) return;
      const saved: unknown = JSON.parse(raw);
      if (
        !isRecord(saved) ||
        typeof saved.accessKey !== 'string' ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(saved.accessKey)
      ) {
        sessionStorage.removeItem(savedOrderStorage);
        return;
      }
      const savedOrder: SavedOrder = {
        accessKey: saved.accessKey,
        order: parseStorefrontOrder(saved.order),
      };
      setOrderAccessKey(savedOrder.accessKey);
      void fetch(`${apiBaseUrl()}/storefront/orders/${savedOrder.order.id}/status`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ accessKey: savedOrder.accessKey }),
        cache: 'no-store',
      })
        .then(async (response) => {
          if (!response.ok) throw new Error(await responseMessage(response));
          const latest = await readOrderResponse(response);
          rememberOrder(savedOrder.accessKey, latest);
        })
        .catch((statusError: unknown) => {
          console.error('Could not restore the last storefront order.', statusError);
          setOrder(savedOrder.order);
          setError('Order status could not be refreshed. The confirmation saved in this browser is shown below.');
        });
    } catch (storageError) {
      console.error('Could not read the saved order confirmation.', storageError);
      setError('The saved order confirmation could not be restored in this browser.');
    }
  }, [checkoutKey, hydrated, items.length, rememberOrder]);

  const refreshOrder = useCallback(async () => {
    if (!order || !orderAccessKey || refreshingOrder) return;
    setRefreshingOrder(true);
    setError(null);
    try {
      const response = await fetch(
        `${apiBaseUrl()}/storefront/orders/${order.id}/status`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ accessKey: orderAccessKey }),
          cache: 'no-store',
        },
      );
      if (!response.ok) throw new Error(await responseMessage(response));
      rememberOrder(orderAccessKey, await readOrderResponse(response));
    } catch (refreshError) {
      setError(
        refreshError instanceof Error
          ? refreshError.message
          : 'Order status could not be refreshed. Try again.',
      );
    } finally {
      setRefreshingOrder(false);
    }
  }, [order, orderAccessKey, refreshingOrder, rememberOrder]);

  const placeOrder = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (submitting || !checkoutKey || !bagCanBeOrdered) return;
    setSubmitting(true);
    setError(null);
    try {
      const response = await fetch(`${apiBaseUrl()}/storefront/orders`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          idempotencyKey: checkoutKey,
          customerName,
          customerPhone,
          customerEmail,
          fulfillmentMethod,
          ...(fulfillmentMethod === 'DELIVERY' ? { deliveryAddress } : {}),
          privacyAccepted,
          lines: cartLines.map(({ product, quantity }) => ({
            productId: product.id,
            quantity,
          })),
        }),
      });
      if (!response.ok) throw new Error(await responseMessage(response));
      const placedOrder = await readOrderResponse(response);
      rememberOrder(checkoutKey, placedOrder);
      sessionStorage.removeItem(checkoutKeyStorage);
      setCheckoutKey('');
      clear();
    } catch (submitError) {
      setError(
        submitError instanceof Error
          ? submitError.message
          : 'Your order could not be placed. Check your connection and retry.',
      );
    } finally {
      setSubmitting(false);
    }
  };

  const cancelOrder = async () => {
    if (!order || !orderAccessKey || cancelling) return;
    setCancelling(true);
    setError(null);
    try {
      const response = await fetch(
        `${apiBaseUrl()}/storefront/orders/${order.id}/cancel`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ accessKey: orderAccessKey }),
        },
      );
      if (!response.ok) throw new Error(await responseMessage(response));
      rememberOrder(orderAccessKey, await readOrderResponse(response));
    } catch (cancelError) {
      setError(
        cancelError instanceof Error
          ? cancelError.message
          : 'This order could not be cancelled. Refresh its status and try again.',
      );
    } finally {
      setCancelling(false);
    }
  };

  const acceptDeliveryFee = async () => {
    if (
      !order ||
      !orderAccessKey ||
      !order.deliveryFeeQuotedAt ||
      order.deliveryFee === null ||
      acceptingFee
    ) {
      return;
    }
    setAcceptingFee(true);
    setError(null);
    try {
      const response = await fetch(
        `${apiBaseUrl()}/storefront/orders/${order.id}/accept-delivery-fee`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            accessKey: orderAccessKey,
            quotedAt: order.deliveryFeeQuotedAt,
          }),
        },
      );
      if (!response.ok) throw new Error(await responseMessage(response));
      rememberOrder(orderAccessKey, await readOrderResponse(response));
    } catch (acceptError) {
      setError(
        acceptError instanceof Error
          ? acceptError.message
          : 'The delivery fee could not be accepted. Refresh the order and try again.',
      );
    } finally {
      setAcceptingFee(false);
    }
  };

  const dismissOrder = () => {
    try {
      sessionStorage.removeItem(savedOrderStorage);
      const nextKey = crypto.randomUUID();
      sessionStorage.setItem(checkoutKeyStorage, nextKey);
      setCheckoutKey(nextKey);
    } catch (storageError) {
      console.error('Could not prepare another storefront checkout.', storageError);
      setError('This browser could not start another checkout. Reload the page and try again.');
      return;
    }
    setOrder(null);
    setOrderAccessKey('');
    setError(null);
  };

  const paymentPending = order?.status === 'AWAITING_PAYMENT';
  const statusLabel =
    order?.status === 'AWAITING_PAYMENT'
      ? 'Awaiting payment'
      : order?.status === 'CANCELLED'
        ? 'Cancelled'
        : 'Reservation expired';

  return (
    <main className="simple-page checkout-page">
      <div className="page-heading-row">
        <div>
          <h1>{order ? 'Order received' : 'Checkout'}</h1>
          <p className="page-intro">
            {order
              ? 'Your order is saved with the shop. No payment has been taken.'
              : 'Add your contact details and choose how you would like to receive your order.'}
          </p>
        </div>
        {!order && (
          <Link className="back-link" href="/cart">
            <span aria-hidden="true">←</span> Back to your bag
          </Link>
        )}
      </div>

      {error && (
        <p className="checkout-error" role="alert">
          {error}
        </p>
      )}

      {order ? (
        <section className="order-confirmation" aria-live="polite">
          <div className="order-confirmation-heading">
            <div>
              <span className={`order-status order-status-${order.status.toLowerCase()}`}>
                {statusLabel}
              </span>
              <h2>{order.orderNumber}</h2>
              <p>
                {paymentPending
                  ? `Unpaid. Your stock hold ends at ${expiryLabel(order.expiresAt)}.`
                  : order.status === 'CANCELLED'
                    ? 'The stock hold has been released.'
                    : 'The 15-minute stock hold has ended and the items are available again.'}
              </p>
            </div>
            <button
              className="button button-secondary"
              type="button"
              onClick={refreshOrder}
              disabled={refreshingOrder}
            >
              {refreshingOrder ? 'Refreshing…' : 'Refresh status'}
            </button>
          </div>

          <div
            className={`order-confirmation-details${order.fulfillmentMethod === 'DELIVERY' ? ' is-delivery' : ''}`}
          >
            <div>
              <span>Receive by</span>
              <strong>
                {order.fulfillmentMethod === 'DELIVERY' ? 'Delivery' : 'Pickup'}
              </strong>
            </div>
            <div>
              <span>Merchandise total</span>
              <strong>{formatStorePrice(order.subtotal)}</strong>
            </div>
            {order.fulfillmentMethod === 'DELIVERY' && (
              <div>
                <span>Delivery charge</span>
                <strong>
                  {order.deliveryFee === null
                    ? 'Pending shop quote'
                    : formatStorePrice(order.deliveryFee)}
                </strong>
              </div>
            )}
            <div>
              <span>
                {order.fulfillmentMethod === 'DELIVERY' && order.deliveryFee === null
                  ? 'Current total before delivery'
                  : 'Order total'}
              </span>
              <strong>{formatStorePrice(order.total)}</strong>
            </div>
            <div>
              <span>Payment</span>
              <strong>Not collected</strong>
            </div>
          </div>

          {order.fulfillmentMethod === 'DELIVERY' && (
            <div className="checkout-section checkout-payment-notice fee-review">
              <h2>
                {order.deliveryFee === null
                  ? 'Delivery charge awaiting shop'
                  : order.deliveryFeeAcceptedAt
                    ? 'Delivery charge accepted'
                    : 'Review delivery charge'}
              </h2>
              <p>
                {order.deliveryFee === null
                  ? paymentPending
                    ? 'The shop has not set a delivery charge yet. Refresh this order to check for an update. You must accept the quoted charge before payment.'
                    : 'The reservation ended before the shop confirmed a delivery charge. The items are available again; place a new order if you still want them.'
                  : order.deliveryFeeAcceptedAt
                    ? 'You accepted this delivery charge. The order total above includes it; payment has not been taken.'
                    : paymentPending
                      ? `The shop quoted ${formatStorePrice(order.deliveryFee)}. Review the updated total of ${formatStorePrice(order.total)} and accept before payment.`
                      : 'This order is no longer active. Its delivery charge cannot be accepted.'}
              </p>
              {order.deliveryFee !== null && !order.deliveryFeeAcceptedAt && paymentPending && (
                <button
                  className="button button-primary"
                  type="button"
                  onClick={acceptDeliveryFee}
                  disabled={acceptingFee}
                >
                  {acceptingFee ? 'Saving acceptance…' : 'Accept delivery fee'}
                </button>
              )}
            </div>
          )}

          <ol className="order-lines" aria-label="Items in this order">
            {order.items.map((line, index) => (
              <li key={`${line.productName}-${index}`}>
                <span>
                  {line.quantity} × {line.productName}
                  {line.variantLabel ? ` · ${line.variantLabel}` : ''}
                </span>
                <strong>{formatStorePrice(line.lineTotal)}</strong>
              </li>
            ))}
          </ol>

          <ol className="order-history" aria-label="Order status history">
            {order.statusEvents.map((event, index) => (
              <li key={`${event.toStatus}-${event.createdAt}-${index}`}>
                <span className="order-history-dot" aria-hidden="true" />
                <div>
                  <strong>
                  {event.detail.startsWith('Delivery fee quoted')
                    ? 'Delivery fee set'
                    : event.detail.startsWith('Customer accepted the delivery fee')
                      ? 'Delivery fee accepted'
                      : event.toStatus === 'AWAITING_PAYMENT'
                        ? 'Order placed'
                        : event.toStatus === 'CANCELLED'
                          ? 'Order cancelled'
                          : 'Stock hold expired'}
                  </strong>
                  <p>{event.detail}</p>
                  <time dateTime={event.createdAt}>
                    {new Date(event.createdAt).toLocaleString()}
                  </time>
                </div>
              </li>
            ))}
          </ol>

          <div className="order-confirmation-actions">
            {paymentPending && (
              <button
                className="button button-secondary"
                type="button"
                onClick={cancelOrder}
                disabled={cancelling}
              >
                {cancelling ? 'Cancelling…' : 'Cancel this order'}
              </button>
            )}
            <button className="text-link" type="button" onClick={dismissOrder}>
              Continue browsing
            </button>
          </div>
        </section>
      ) : !hydrated || !storefrontProfileLoaded ? (
        <div className="catalog-empty" aria-live="polite">
          Loading checkout…
        </div>
      ) : cartLines.length === 0 ? (
        <div className="cart-empty">
          <h2>Your bag is empty</h2>
          <p>Add published products before starting checkout.</p>
          <Link className="button button-primary" href="/#products">
            Browse products
          </Link>
        </div>
      ) : catalogState !== 'live' ? (
        <div className="checkout-blocked" role="status">
          <h2>Checkout needs the shop’s live catalog</h2>
          <p>
            Sample items and offline catalog data can’t be submitted as real
            orders. Return when the shop’s published products are available.
          </p>
          <Link className="button button-secondary" href="/#products">
            Return to the storefront
          </Link>
        </div>
      ) : !fulfillmentAvailable ? (
        <div className="checkout-blocked" role="status">
          <h2>This shop has not enabled delivery or pickup</h2>
          <p>Contact the shop or come back after it configures an order option.</p>
          <Link className="button button-secondary" href="/policies">
            View store information
          </Link>
        </div>
      ) : (
        <>
          {!bagCanBeOrdered && (
            <p className="checkout-error" role="alert">
              One or more items are unavailable. Remove them from your bag before placing an order.
            </p>
          )}
          <form className="checkout-layout" onSubmit={placeOrder}>
            <div className="checkout-main">
              <section className="checkout-section">
                <h2>Your contact details</h2>
                <div className="checkout-fields">
                  <label className="checkout-field">
                    <span>Full name</span>
                    <input
                      autoComplete="name"
                      maxLength={120}
                      minLength={2}
                      name="customerName"
                      onChange={(event) => setCustomerName(event.target.value)}
                      required
                      value={customerName}
                    />
                  </label>
                  <label className="checkout-field">
                    <span>Mobile number</span>
                    <input
                      autoComplete="tel"
                      inputMode="tel"
                      maxLength={16}
                      name="customerPhone"
                      onChange={(event) => setCustomerPhone(event.target.value)}
                      pattern="((\+?254|0)[ -]?)?[17]([ -]?[0-9]){8}"
                      placeholder="07xx xxx xxx"
                      required
                      title="Enter a valid Kenyan mobile number."
                      value={customerPhone}
                    />
                  </label>
                  <label className="checkout-field">
                    <span>Email <small>Optional</small></span>
                    <input
                      autoComplete="email"
                      maxLength={254}
                      name="customerEmail"
                      onChange={(event) => setCustomerEmail(event.target.value)}
                      type="email"
                      value={customerEmail}
                    />
                  </label>
                </div>
              </section>

              <section className="checkout-section">
                <h2>How would you like to receive it?</h2>
                <div className="fulfillment-options">
                  {deliveryAvailable && (
                    <label className="fulfillment-option">
                      <input
                        checked={fulfillmentMethod === 'DELIVERY'}
                        name="fulfillmentMethod"
                        onChange={() => setFulfillmentMethod('DELIVERY')}
                        type="radio"
                        value="DELIVERY"
                      />
                      <span>
                        <strong>Delivery</strong>
                        <small>{storefrontProfile.deliveryDetails || 'The shop will confirm delivery details.'}</small>
                      </span>
                    </label>
                  )}
                  {pickupAvailable && (
                    <label className="fulfillment-option">
                      <input
                        checked={fulfillmentMethod === 'PICKUP'}
                        name="fulfillmentMethod"
                        onChange={() => setFulfillmentMethod('PICKUP')}
                        type="radio"
                        value="PICKUP"
                      />
                      <span>
                        <strong>Pickup</strong>
                        <small>{storefrontProfile.pickupDetails || storefrontProfile.address || 'The shop will confirm pickup details.'}</small>
                      </span>
                    </label>
                  )}
                </div>
                {fulfillmentMethod === 'DELIVERY' && (
                  <label className="checkout-field checkout-address">
                    <span>Delivery address</span>
                    <textarea
                      autoComplete="street-address"
                      maxLength={500}
                      minLength={5}
                      name="deliveryAddress"
                      onChange={(event) => setDeliveryAddress(event.target.value)}
                      required
                      rows={3}
                      value={deliveryAddress}
                    />
                  </label>
                )}
              </section>

              <section className="checkout-section checkout-payment-notice">
                <h2>Payment and delivery charge</h2>
                <p>
                  This creates an unpaid order only. No money is taken here.
                  For delivery, the shop sets the charge and you must review and
                  accept it before payment.
                </p>
                <p>Stock is held for 15 minutes from order placement.</p>
              </section>

              <label className="checkout-consent">
                <input
                  checked={privacyAccepted}
                  onChange={(event) => setPrivacyAccepted(event.target.checked)}
                  required
                  type="checkbox"
                />
                <span>
                  I understand the shop will use my contact details to handle
                  this order.{' '}
                  {storefrontProfile.policies.privacy ? (
                    <>
                      Read the shop’s{' '}
                      <Link href="/policies#privacy">privacy information</Link>.
                    </>
                  ) : (
                    <>
                      The shop has not provided a privacy policy.{' '}
                      <Link href="/policies#privacy">View store information</Link>.
                    </>
                  )}
                </span>
              </label>
            </div>

            <aside className="checkout-summary" aria-label="Order summary">
              <h2>Your order</h2>
              <ul className="checkout-summary-lines">
                {cartLines.map(({ product, quantity }) => (
                  <li key={product.id}>
                    <span>
                      {quantity} × {product.name}
                      {product.variantLabel ? ` · ${product.variantLabel}` : ''}
                    </span>
                    <strong>{formatStorePrice(product.salePrice * quantity)}</strong>
                  </li>
                ))}
              </ul>
              <div className="summary-row">
                <span>Merchandise total</span>
                <strong>{formatStorePrice(subtotal)}</strong>
              </div>
              <p className="summary-note">
                Prices and stock are checked again by the shop when you place
                the order. For delivery, the shop will quote a charge for you
                to review before payment.
              </p>
              <button
                className="button button-primary checkout-submit"
                disabled={
                  submitting ||
                  !checkoutKey ||
                  !bagCanBeOrdered ||
                  !privacyAccepted
                }
                type="submit"
              >
                {submitting ? 'Placing order…' : 'Place unpaid order'}
              </button>
              <p className="checkout-no-payment">No payment collected at this step</p>
            </aside>
          </form>
        </>
      )}
    </main>
  );
}
