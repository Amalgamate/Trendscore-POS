import {
  type PaymentMethod,
  type PaymentProvider,
  type ProcessPaymentRequest,
  type ProcessPaymentResult,
  PaymentError,
} from './types.js';

/**
 * Provider registry.
 *
 * The POS asks for a method and gets a provider. Adding M-Pesa, or card
 * later, means registering an implementation here and nothing else.
 */
export class PaymentRegistry {
  private readonly providers = new Map<PaymentMethod, PaymentProvider>();

  register(provider: PaymentProvider): this {
    this.providers.set(provider.method, provider);
    return this;
  }

  get(method: PaymentMethod): PaymentProvider {
    const p = this.providers.get(method);
    if (!p) throw new PaymentError(`No provider for method ${method}`, 'NO_PROVIDER');
    return p;
  }

  has(method: PaymentMethod): boolean {
    return this.providers.has(method);
  }

  enabledMethods(): PaymentMethod[] {
    return [...this.providers.keys()];
  }

  /** Single entry point used by the POS. */
  async process(
    method: PaymentMethod,
    req: ProcessPaymentRequest,
  ): Promise<ProcessPaymentResult> {
    return this.get(method).processPayment(req);
  }
}
