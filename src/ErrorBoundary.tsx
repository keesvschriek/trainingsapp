import { Component, type ReactNode } from 'react';

/**
 * Vangnet: loopt een scherm vast door een fout, dan blijft de rest van de app werken
 * (tabbalk, sync, andere schermen) in plaats van een wit scherm.
 */
export class ErrorBoundary extends Component<{ children: ReactNode; onHome?: () => void }, { error: Error | null }> {
  state: { error: Error | null } = { error: null };

  static getDerivedStateFromError(error: Error) {
    return { error };
  }

  componentDidCatch(error: Error) {
    console.error('Scherm liep vast:', error);
  }

  render() {
    const { error } = this.state;
    if (!error) return this.props.children;
    return (
      <div className="card">
        <strong>{this.props.onHome ? 'Dit scherm liep vast' : 'Dit onderdeel liep vast'}</strong>
        <p className="muted small">Je gegevens zijn veilig. Probeer het opnieuw, of ga naar Vandaag.</p>
        <p className="muted small" style={{ wordBreak: 'break-word' }}>{String(error.message || error)}</p>
        <div className="row mt">
          <button className="btn" onClick={() => this.setState({ error: null })}>Opnieuw</button>
          {this.props.onHome && (
            <button className="btn secondary" onClick={() => { this.setState({ error: null }); this.props.onHome!(); }}>Naar Vandaag</button>
          )}
        </div>
      </div>
    );
  }
}
