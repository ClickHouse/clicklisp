import Header from "./sections/Header";
import Hero from "./sections/Hero";
import Features from "./sections/Features";
import Language from "./sections/Language";
import Rules from "./sections/Rules";
import Udfs from "./sections/Udfs";
import Playground from "./sections/Playground";
import GetStarted from "./sections/GetStarted";
import Faq from "./sections/Faq";
import Footer from "./sections/Footer";

export default function App() {
  return (
    <>
      <Header />
      <main>
        <Hero />
        <Features />
        <Language />
        <Rules />
        <Udfs />
        <Playground />
        <GetStarted />
        <Faq />
      </main>
      <Footer />
    </>
  );
}
