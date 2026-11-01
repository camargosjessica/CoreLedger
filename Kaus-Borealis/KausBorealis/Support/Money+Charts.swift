import Charts
import KausMedia

/// Os gráficos plotam reais como `Double`; a soma continua exata em `Money`
/// e só a posição na tela vira ponto flutuante.
extension Money: @retroactive Plottable {
    public var primitivePlottable: Double { doubleValue }

    public init?(primitivePlottable: Double) {
        self.init(primitivePlottable)
    }
}
