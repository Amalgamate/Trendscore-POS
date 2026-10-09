const policies = [
  {
    id: 'delivery',
    title: 'Delivery & pickup',
  },
  {
    id: 'returns',
    title: 'Returns & refunds',
  },
  {
    id: 'privacy',
    title: 'Privacy',
  },
  {
    id: 'terms',
    title: 'Terms of sale',
  },
];

export default function StorePoliciesPage() {
  return (
    <main className="simple-page">
      <p className="eyebrow">STORE INFORMATION</p>
      <h1>Policies</h1>
      <p className="page-intro">
        The shop will provide and approve its own policy wording before the
        storefront is published.
      </p>
      <div className="policy-list">
        {policies.map((policy) => (
          <section id={policy.id} key={policy.id}>
            <h2>{policy.title}</h2>
            <p>Not configured by this shop yet.</p>
          </section>
        ))}
      </div>
    </main>
  );
}
