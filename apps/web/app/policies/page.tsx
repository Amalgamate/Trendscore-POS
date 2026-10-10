'use client';

import { useStoreCart } from '../store-cart';

const policies = [
  {
    id: 'delivery',
    title: 'Delivery & pickup',
    key: 'delivery',
  },
  {
    id: 'returns',
    title: 'Returns & refunds',
    key: 'returns',
  },
  {
    id: 'privacy',
    title: 'Privacy',
    key: 'privacy',
  },
  {
    id: 'terms',
    title: 'Terms of sale',
    key: 'terms',
  },
] as const;

export default function StorePoliciesPage() {
  const { storefrontProfile } = useStoreCart();

  return (
    <main className="simple-page">
      <p className="eyebrow">STORE INFORMATION</p>
      <h1>Policies</h1>
      <p className="page-intro">
        Information provided by {storefrontProfile.storeName}.
      </p>
      <div className="policy-list">
        {policies.map((policy) => (
          <section id={policy.id} key={policy.id}>
            <h2>{policy.title}</h2>
            {storefrontProfile.policies[policy.key] ? (
              <p className="policy-copy">
                {storefrontProfile.policies[policy.key]}
              </p>
            ) : (
              <p className="policy-not-provided">
                This shop has not provided this policy yet.
              </p>
            )}
          </section>
        ))}
      </div>
    </main>
  );
}
